"""Agentic director: sarvam-105b tool calling over Immich tools, then the same server-side validation."""
from __future__ import annotations

import json
import logging
import time
from typing import Any

from . import director
from .immich import ImmichClient
from .music import beat_interval, pick_track
from .sarvam import SarvamClient, parse_json_tolerant
from .timing import event

log = logging.getLogger("memories.agentic")

FREE_ROUNDS = 2   # rounds 3-4 force submit_edit
MAX_ROUNDS = 4

CLIP = {"type": "object", "properties": {"asset_id": {"type": "string"}, "in_s": {"type": "number"},
        "out_s": {"type": "number"}, "hold_s": {"type": "number"}, "caption": {"type": "string"}},
        "required": ["asset_id"]}
CUT = {"type": "object", "properties": {"title": {"type": "string"}, "why": {"type": "string"},
       "clips": {"type": "array", "items": CLIP}, "music_mood": {"type": "string"},
       "caption_language": {"type": "string"}, "cover_asset_id": {"type": "string"}},
       "required": ["title", "why", "clips", "music_mood", "cover_asset_id"]}

TOOLS = [
    {"type": "function", "function": {"name": "search_moments", "description": "Semantic (CLIP) search of the event album, e.g. 'aarti', 'family group photo', 'fireworks'. Returns the best matching shots with alias, caption, quality.",
     "parameters": {"type": "object", "properties": {"query": {"type": "string"}, "limit": {"type": "integer"}}, "required": ["query"]}}},
    {"type": "function", "function": {"name": "find_team_moments", "description": "Shots of the requester's OWN team (recurring faces across the album + building together at laptops, group poses, selfies), in time order, with team_score. Use this first whenever the request mentions team/friends/dost/my people.",
     "parameters": {"type": "object", "properties": {"limit": {"type": "integer"}}}}},
    {"type": "function", "function": {"name": "list_people", "description": "People recognised in the album with how many shots each appears in.",
     "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {"name": "assets_with", "description": "Shots that contain ALL the given people (names from list_people).",
     "parameters": {"type": "object", "properties": {"people": {"type": "array", "items": {"type": "string"}}}, "required": ["people"]}}},
    {"type": "function", "function": {"name": "shot_details", "description": "Full details (caption, quality, mood, time, video duration, people) for shot aliases.",
     "parameters": {"type": "object", "properties": {"asset_ids": {"type": "array", "items": {"type": "string"}}}, "required": ["asset_ids"]}}},
    {"type": "function", "function": {"name": "submit_edit", "description": "Submit the final edit: exactly 2 cuts with different intent. Use only aliases you have seen in tool results.",
     "parameters": {"type": "object", "properties": {"cuts": {"type": "array", "items": CUT}}, "required": ["cuts"]}}},
]

AGENT_SYSTEM = director.SYSTEM_PROMPT + """
You work like an editor with tools over the album. The first tool results are already in the conversation, plus the top shots table. At most ONE more round of tool calls (parallel calls are fine), then call submit_edit with both cuts. Use only aliases (A1, A2, ...) you have seen."""


def _brief(r: dict) -> dict:
    an = r.get("analysis") or {}
    return {"alias": r["alias"], "type": "video" if r["type"] == "VIDEO" else "photo", "time": (r.get("time") or "")[11:16],
            "caption": an.get("caption"), "quality": an.get("quality"), "mood": an.get("mood"),
            "people": r.get("people") or [], "activity": an.get("activity"), "team_score": r.get("team_score"),
            **({"duration_s": round(r.get("duration", 0), 1), "best_window": an.get("best_window")} if r["type"] == "VIDEO" else {})}


async def plan_agentic(sarvam: SarvamClient, immich: ImmichClient, album_id: str, rows: list[dict], prompt: str,
                       destination: str, member: str | None, language: str | None, album_name: str) -> tuple[list[dict], dict]:
    by_id = {r["id"]: r for r in rows}
    by_alias = {r["alias"]: r for r in rows}
    btrack = director.beat_track(prompt)
    beat = beat_interval(btrack)
    language = language or director.detect_language(prompt)
    d = director.DESTINATIONS.get(destination, director.DESTINATIONS["wa_status"])
    people_counts: dict[str, int] = {}
    for r in rows:
        for n in r.get("people") or []:
            people_counts[n] = people_counts.get(n, 0) + 1
    overview = (f"Event album: {album_name or '-'}; {len(rows)} shots "
                f"({sum(1 for r in rows if r['type'] == 'VIDEO')} videos), from {(rows[0].get('time') or '')[11:16] if rows else '-'} "
                f"to {(rows[-1].get('time') or '')[11:16] if rows else '-'}.\n"
                f"Requesting member: {member or '-'}\nRequest: {prompt or 'two nice reels'}\n"
                f"Caption language: {language}\nDestination: {destination} ({d['label']}), aim ~{d['target']:.0f} s per cut.\n"
                f"Music beat interval: {beat:.3f} s")
    messages: list[dict] = [{"role": "system", "content": AGENT_SYSTEM}, {"role": "user", "content": overview}]
    trace: list[dict] = []

    async def run_tool(name: str, args: dict) -> Any:
        if name == "search_moments":
            q = str(args.get("query", ""))
            lim = int(args.get("limit") or 8)
            try:
                hits = await immich.smart_search(q, album_id, size=min(lim, 15))
                out = [_brief(by_id[h["id"]]) for h in hits if h["id"] in by_id]
            except Exception as e:  # fall back to caption match
                ql = q.lower()
                out = [_brief(r) for r in rows if ql in ((r.get("analysis") or {}).get("caption") or "").lower()][:lim]
                if not out:
                    out = [{"error": f"search failed: {type(e).__name__}"}]
            return out[:lim]
        if name == "find_team_moments":
            from .grammar import team_ok
            lim = int(args.get("limit") or 20)
            team_rows = sorted([r for r in rows if team_ok(r) and director.usable(r)], key=lambda r: -(r.get("team_score") or 0))[:lim]
            return [_brief(r) for r in sorted(team_rows, key=lambda r: r.get("time") or "")]
        if name == "list_people":
            return [{"name": n, "shots": c} for n, c in sorted(people_counts.items(), key=lambda x: -x[1])]
        if name == "assets_with":
            want = {str(p).lower() for p in args.get("people") or []}
            return [_brief(r) for r in rows if want and want <= {n.lower() for n in r.get("people") or []}][:20]
        if name == "shot_details":
            return [_brief(by_alias[a]) for a in args.get("asset_ids") or [] if a in by_alias]
        return {"error": f"unknown tool {name}"}

    from .grammar import parse_intent, shot_value
    intent = parse_intent(prompt)
    t_start = time.perf_counter()
    # seed: a good first tool call, executed by us (saves a round trip)
    seed = [("find_team_moments", {"limit": 20})] if intent["subject"] == "team" else \
           [("search_moments", {"query": prompt or "best moments", "limit": 12})]
    seed_calls = []
    for k, (name, args) in enumerate(seed):
        seed_calls.append({"id": f"seed{k}", "type": "function", "function": {"name": name, "arguments": json.dumps(args)}})
    messages.append({"role": "assistant", "content": "", "tool_calls": seed_calls})
    for c, (name, args) in zip(seed_calls, seed):
        res = await run_tool(name, args)
        messages.append({"role": "tool", "tool_call_id": c["id"], "content": json.dumps(res, ensure_ascii=False)})
    top = sorted(director.table_rows(rows), key=lambda r: -shot_value(r, intent["topics"], intent["subject"]))[:40]
    messages.append({"role": "user", "content": f"Parsed intent: {json.dumps(intent)}\nTop shots by value:\n"
                     + director.table_text(sorted(top, key=lambda r: r.get("time") or ""))
                     + "\nNow either make one more round of tool calls or call submit_edit."})
    trace: list[dict] = [{"round": 0, "seed": [n for n, _ in seed]}]
    submitted: Any = None
    force = False
    for rnd in range(1, MAX_ROUNDS + 1):
        params: dict[str, Any] = {"tools": TOOLS, "reasoning_effort": "low", "max_tokens": 5000, "temperature": 0.4}
        if force or rnd > FREE_ROUNDS:
            params["tool_choice"] = {"type": "function", "function": {"name": "submit_edit"}}
        t0 = time.perf_counter()
        resp = await sarvam.chat("sarvam-105b", messages, kind=f"agent_round{rnd}", **params)
        msg = (resp.get("choices") or [{}])[0].get("message") or {}
        calls = msg.get("tool_calls") or []
        step = {"round": rnd, "ms": round((time.perf_counter() - t0) * 1000), "tool_calls": [], "forced": "tool_choice" in params}
        if not calls:
            try:
                submitted = parse_json_tolerant(msg.get("content") or "")
                if not isinstance(submitted, (dict, list)) or not (submitted.get("cuts") if isinstance(submitted, dict) else submitted):
                    raise ValueError("no cuts")
                step["text_submit"] = True
                trace.append(step)
                break
            except Exception:
                submitted = None
                messages.append({"role": "assistant", "content": msg.get("content") or ""})
                messages.append({"role": "user", "content": "Call submit_edit now with both cuts."})
                force = True  # empty round: force submit_edit immediately
                trace.append(step)
                continue
        messages.append({"role": "assistant", "content": msg.get("content") or "", "tool_calls": calls})
        for c in calls:
            fn = c.get("function") or {}
            name = fn.get("name")
            try:
                args = json.loads(fn.get("arguments") or "{}")
            except Exception:
                args = {}
            if name == "submit_edit":
                if args.get("cuts"):
                    submitted = args
                step["tool_calls"].append({"name": name, "cuts": len(args.get("cuts") or [])})
                messages.append({"role": "tool", "tool_call_id": c.get("id"), "content": json.dumps({"ok": bool(args.get("cuts"))})})
                continue
            res = await run_tool(name, args)
            step["tool_calls"].append({"name": name, "args": args, "results": len(res) if isinstance(res, list) else 1})
            messages.append({"role": "tool", "tool_call_id": c.get("id"), "content": json.dumps(res, ensure_ascii=False)})
        trace.append(step)
        if submitted is not None:
            break
        force = True  # one exploration round is enough
    if submitted is None:
        raise RuntimeError("agent did not submit an edit")
    cuts, notes = director.validate_edl(submitted, rows, destination, beat,
                                        ctx={"prompt": prompt, "language": language, "album_name": album_name})
    if not any(c.get("source") == "director" for c in cuts):
        raise RuntimeError("agent edit invalid after validation: " + "; ".join(notes[:5]))
    director.assign_music(cuts, btrack)
    event("agentic plan", rounds=len(trace), ms=round((time.perf_counter() - t_start) * 1000))
    return cuts, {"strategy": "agentic", "label": "director", "notes": notes, "tool_trace": trace,
                  "beat_s": round(beat, 3), "language": language}
