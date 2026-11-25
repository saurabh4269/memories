"""The director: asset table -> sarvam-105b -> EDL JSON -> validated, fitted, beat-snapped cuts."""
from __future__ import annotations

import difflib
import json
import logging
import re
from typing import Any

from .music import beat_interval, pick_track, tracks

log = logging.getLogger("memories.director")

DESTINATIONS: dict[str, dict] = {
    "insta_reel": {"min": 15.0, "max": 25.0, "target": 20.0, "label": "Instagram Reel 9:16, 15-25 s"},
    "wa_status": {"min": 15.0, "max": 20.0, "target": 17.5, "label": "WhatsApp Status 9:16, 15-20 s"},
    "insta_story": {"min": 10.0, "max": 15.0, "target": 13.0, "label": "Instagram Story 9:16, 10-15 s"},
}
MOODS = ["joyful", "emotional", "calm", "festive", "candid", "funny", "formal"]
MIN_QUALITY = 4
PHOTO_MIN, PHOTO_MAX, PHOTO_DEFAULT = 1.2, 4.5, 2.4
VIDEO_MIN, VIDEO_MAX = 1.2, 6.0


# ---------------------------------------------------------------- asset table

def asset_rows(assets: list[dict]) -> list[dict]:
    """Normalise Immich assets + analysis into compact rows with short aliases (A1, A2, ...)."""
    rows = []
    for i, a in enumerate(sorted(assets, key=lambda x: x.get("time") or "")):
        rows.append({**a, "alias": f"A{i + 1}"})
    return rows


def table_rows(rows: list[dict]) -> list[dict]:
    """Rows worth showing the model: usable, not a near-duplicate of an earlier better row."""
    out: list[dict] = []
    for r in rows:
        if not usable(r):
            continue
        if any(near_duplicate(r, o) for o in out):
            continue
        out.append(r)
    return out


def table_text(rows: list[dict]) -> str:
    lines = ["alias|type|time|people|caption|quality|mood|group|dur_s(best window)|moment|activity|team"]
    for r in rows:
        an = r.get("analysis") or {}
        lines.append("|".join([
            r["alias"], "V" if r["type"] == "VIDEO" else "P", (r.get("time") or "")[11:16],
            ",".join(r.get("people") or []) or "-", (an.get("caption") or "-").replace("|", "/"),
            str(an.get("quality", "?")), an.get("mood", "-"), "y" if an.get("is_group") else "n",
            (f"{r.get('duration', 0):.0f}" + (f"({an['best_window'][0]:.1f}-{an['best_window'][1]:.1f})"
             if an.get("best_window") and an["best_window"][1] > 0 else "")) if r["type"] == "VIDEO" else "-",
            an.get("moment_tag") or "-", an.get("activity") or "-",
            f"{r.get('team_score', 0):.0f}" if r.get("team_score") is not None else "-",
        ]))
    return "\n".join(lines)


SYSTEM_PROMPT = """You are Memories' film director: a top Indian wedding/festival reel editor.
You turn a family's shared event album into TWO different short vertical reels for one person.
Input: the person's request (Hindi, English or Hinglish), the destination with its length limits, music beat interval, and a table of shots (alias|type P=photo V=video|time HH:MM|people|caption|quality 1-10|mood|group y/n|video duration|moment).
Rules:
- Output JSON only, no prose. Exactly 2 cuts with clearly different intent, e.g. cut 1 "the story in order" (chronological, everyone, holds ~1.8-2.8 s) and cut 2 "best moments on the beat" (punchy, the strongest shots, holds 0.6-1.2 s, more clips). Cut 2 may reuse at most 3 shots of cut 1. Adapt the intent to the request.
- Open each cut with the strongest people/emotion shot (the hook). End cut 1 on a group photo held >= 2 s. Never repeat a shot inside a cut.
- Use only aliases from the table (asset_id = alias like "A12"). Skip low quality (<4) shots. No two near-identical shots in a cut.
- Each cut has 6-12 clips. Photos: hold_s (1.2-4.5 s, multiples of the beat interval feel best). Videos: in_s and out_s inside the video duration, 1.5-6 s long, the most interesting part.
- Total cut length must fit the destination limits.
- Favour shots with the requesting member and the people the request mentions; for "emotional", favour family groups, elders, blessings, aarti, hugs; for "fun", candid and funny shots.
- "team" column = team_score: how surely the shot shows the requester's OWN team (recurring faces + building together). Strangers, organisers, sponsor booths and corridors are NOT the team. If the request is about the team / friends / "my people", use only shots with team >= 3 (team at laptops, coding, group pose, selfie) and end on the team group shot. Tell the team's story over the day: arrival -> building -> late-night grind -> demo/stage -> group photo.
- If the request says "only/sirf X", use only X shots.
- Videos: pick their best 1.5-3 s (in_s/out_s). Photos 1.2-3 s. Never use the same video twice.
- caption: very short (2-4 words), on 3-5 clips per cut (title on the first clip counts), natural and specific to THAT shot, in the caption_language (use "hinglish" = Hindi in Latin script when the request is Hinglish; "hi" = Devanagari; "en" = English).
- title: 2-5 words in the person's language style, and it must be true of the clips (do not say "team" unless the clips show the team). why: one line on why this cut suits the request.
- music_mood: one of joyful, emotional, calm, festive, candid, funny, formal. cover_asset_id: the best photo alias for the cover.
JSON shape:
{"cuts":[{"title":"...","why":"...","clips":[{"asset_id":"A3","in_s":0,"out_s":0,"hold_s":2.4,"caption":""}],"music_mood":"emotional","caption_language":"hinglish","cover_asset_id":"A3"}]}"""


def _intent(prompt: str) -> dict:
    from .grammar import parse_intent
    return parse_intent(prompt)


def user_prompt(prompt: str, destination: str, member: str | None, language: str | None, rows: list[dict],
                beat_s: float, album_name: str = "") -> str:
    d = DESTINATIONS.get(destination, DESTINATIONS["wa_status"])
    return (
        f"Event album: {album_name or '-'}\n"
        f"Requesting member: {member or '-'}\n"
        f"Request: {prompt or 'make two nice reels of the event'}\n"
        f"Preferred caption language: {language or 'match the request'}\n"
        f"Destination: {destination} ({d['label']}); aim for about {d['target']:.0f} s per cut.\n"
        f"Parsed intent: {json.dumps(_intent(prompt))}\n"
        f"Music beat interval: {beat_s:.3f} s\n"
        f"Shots ({len(table_rows(rows))}):\n{table_text(table_rows(rows))}\n"
        "Return the JSON now."
    )


# ---------------------------------------------------------------- validation

def _num(v: Any, default: float = 0.0) -> float:
    try:
        f = float(v)
        return f if f == f else default
    except Exception:
        return default


def snap(value: float, beat: float, lo: float, hi: float) -> float:
    """Snap to a whole number of beats, staying within [lo, hi] (hi wins if no multiple fits)."""
    if beat <= 0:
        return round(min(max(value, lo), hi), 3)
    k = max(1, round(value / beat))
    v = k * beat
    while v > hi + 1e-6 and k > 1:
        k -= 1
        v = k * beat
    while v < lo - 1e-6 and (k + 1) * beat <= hi + 1e-6:
        k += 1
        v = k * beat
    return round(min(v, hi), 3)


def clip_len(c: dict) -> float:
    return c["out_s"] - c["in_s"] if c["kind"] == "video" else c["hold_s"]


def _minute(t: str | None) -> str:
    return (t or "")[:16]


def near_duplicate(a: dict, b: dict) -> bool:
    ha, hb = a.get("phash"), b.get("phash")
    if ha is not None and hb is not None and bin(int(ha) ^ int(hb)).count("1") <= 10:
        return True
    if (a.get("analysis") or {}).get("dup_of") == b.get("id") or (b.get("analysis") or {}).get("dup_of") == a.get("id"):
        return True
    if _minute(a.get("time")) != _minute(b.get("time")) or not a.get("time"):
        return False
    ca = ((a.get("analysis") or {}).get("caption") or "").lower()
    cb = ((b.get("analysis") or {}).get("caption") or "").lower()
    if not ca or not cb:
        return False
    return difflib.SequenceMatcher(None, ca, cb).ratio() > 0.7


def usable(a: dict) -> bool:
    fa = a.get("facet") or {}
    if fa.get("blink") or fa.get("duplicate_of") or (fa.get("burst_group") and fa.get("is_burst_lead") is False):
        return False
    an = a.get("analysis")
    if not an:
        return True
    return not an.get("blurry") and int(an.get("quality", 5)) >= MIN_QUALITY


def make_clip(a: dict, beat: float, in_s: float = 0.0, out_s: float = 0.0, hold_s: float = 0.0, caption: str = "") -> dict | None:
    if a["type"] == "VIDEO":
        dur = float(a.get("duration") or 0)
        if dur < 1.0:
            return None
        in_s = min(max(0.0, _num(in_s)), max(0.0, dur - VIDEO_MIN))
        out_s = _num(out_s)
        if out_s <= in_s:
            out_s = in_s + min(4.0, dur - in_s)
        out_s = min(out_s, dur)
        length = snap(out_s - in_s, beat, VIDEO_MIN, min(VIDEO_MAX, dur - in_s))
        return {"asset_id": a["id"], "kind": "video", "in_s": round(in_s, 3), "out_s": round(in_s + length, 3),
                "hold_s": 0.0, "caption": caption, "max_len": round(dur - in_s, 3)}
    hold = snap(_num(hold_s, PHOTO_DEFAULT) or PHOTO_DEFAULT, beat, PHOTO_MIN, PHOTO_MAX)
    return {"asset_id": a["id"], "kind": "photo", "in_s": 0.0, "out_s": 0.0, "hold_s": hold, "caption": caption,
            "max_len": PHOTO_MAX}


def set_len(c: dict, length: float, beat: float) -> None:
    if c["kind"] == "video":
        c["out_s"] = round(c["in_s"] + snap(length, beat, VIDEO_MIN, min(VIDEO_MAX, c["max_len"])), 3)
    else:
        c["hold_s"] = snap(length, beat, PHOTO_MIN, PHOTO_MAX)


def fit_length(clips: list[dict], by_id: dict[str, dict], dest: dict, beat: float, pool: list[dict],
               pace_max: float | None = None) -> list[dict]:
    """Make the total land inside [min, max]: drop worst / shrink if long; extend / add if short."""
    total = lambda: sum(clip_len(c) for c in clips)  # noqa: E731
    q = lambda c: int((by_id[c["asset_id"]].get("analysis") or {}).get("quality", 5))  # noqa: E731
    while total() > dest["max"] and len(clips) > 3:
        worst = min(range(len(clips)), key=lambda i: (q(clips[i]), -clip_len(clips[i])))
        clips.pop(worst)
    for _ in range(12):
        if total() <= dest["max"]:
            break
        longest = max(clips, key=clip_len)
        before = clip_len(longest)
        set_len(longest, before - beat, beat)
        if clip_len(longest) >= before:
            break
    # extend if short
    for _ in range(40):
        if total() >= dest["min"]:
            break
        grown = False
        for c in sorted(clips, key=clip_len):
            if total() >= dest["min"]:
                break
            if pace_max and c["kind"] == "photo" and c["hold_s"] + beat > pace_max + 1e-6:
                continue
            before = clip_len(c)
            set_len(c, before + beat, beat)
            if clip_len(c) > before + 1e-6 and total() <= dest["max"]:
                grown = True
            elif clip_len(c) > before:
                set_len(c, before, beat)
        if not grown:
            used = {c["asset_id"] for c in clips}
            extra = next((a for a in pool if a["id"] not in used and usable(a)
                          and not any(near_duplicate(a, by_id[u]) for u in used if u in by_id)), None)
            if extra is None:
                break
            nc = make_clip(extra, beat, hold_s=min(PHOTO_DEFAULT, pace_max or PHOTO_DEFAULT), out_s=3.0)
            pool = [a for a in pool if a["id"] != extra["id"]]
            if nc:
                clips.append(nc)
    return clips


def hook_score(r: dict) -> float:
    an = r.get("analysis") or {}
    return int(an.get("quality", 5)) * (1 + min(4, int(an.get("people_count", 0) or 0)) * 0.25) + (2 if an.get("is_group") else 0)


def finish_cut(clips: list[dict], by_id: dict, title: str, notes: list[str]) -> list[dict]:
    """Edit grammar: unique assets; hook = strongest people shot first; title card on the opener."""
    seen_ids: set[str] = set()
    uniq = []
    for c in clips:
        if c["asset_id"] in seen_ids:
            notes.append("dropped repeated asset")
            continue
        seen_ids.add(c["asset_id"])
        uniq.append(c)
    clips = uniq
    if clips:
        best = max(range(len(clips)), key=lambda i: hook_score(by_id[clips[i]["asset_id"]]))
        if best != 0:
            clips.insert(0, clips.pop(best))
        if title and not clips[0].get("caption"):
            clips[0]["caption"] = title[:40]
    return clips


def validate_cut(raw: dict, rows: list[dict], dest: dict, beat: float, pace_max: float | None = None,
                 avoid: set[str] | None = None, ctx: dict | None = None) -> tuple[dict | None, list[str]]:
    notes: list[str] = []
    by_alias = {r["alias"]: r for r in rows}
    by_id = {r["id"]: r for r in rows}
    clips: list[dict] = []
    seen: list[dict] = []
    for c in raw.get("clips") or []:
        if not isinstance(c, dict):
            continue
        key = str(c.get("asset_id", "")).strip()
        a = by_alias.get(key) or by_alias.get(key.upper()) or by_id.get(key)
        if a is None:
            notes.append(f"dropped unknown id {key!r}")
            continue
        if not usable(a):
            notes.append(f"dropped low quality/blurry {a['alias']}")
            continue
        if any(s["id"] == a["id"] for s in seen):
            notes.append(f"dropped repeat {a['alias']}")
            continue
        if any(near_duplicate(a, s) for s in seen):
            notes.append(f"dropped near-duplicate {a['alias']}")
            continue
        cap = str(c.get("caption") or "").strip()[:60]
        clip = make_clip(a, beat, c.get("in_s", 0), c.get("out_s", 0), c.get("hold_s", PHOTO_DEFAULT), cap)
        if clip is None:
            notes.append(f"dropped unusable video {a['alias']}")
            continue
        clips.append(clip)
        seen.append(a)
    if len(clips) < 3:
        return None, notes + ["too few valid clips"]
    if ctx is not None:
        return _grammar_cut(raw, clips, rows, beat, pace_max is not None, ctx, notes)
    pool = sorted([r for r in rows if usable(r) and not any(near_duplicate(r, s) for s in seen)],
                  key=lambda r: -int((r.get("analysis") or {}).get("quality", 5)))
    if pace_max:
        for c in clips:
            if c["kind"] == "photo" and c["hold_s"] > pace_max:
                c["hold_s"] = snap(pace_max, beat, PHOTO_MIN, pace_max)
    clips = fit_length(clips, by_id, dest, beat, pool, pace_max)
    clips = finish_cut(clips, by_id, str(raw.get("title") or ""), notes)
    ids = [c["asset_id"] for c in clips]
    cover = raw.get("cover_asset_id")
    cover_row = by_alias.get(str(cover)) or by_id.get(str(cover))
    cover_id = cover_row["id"] if cover_row and cover_row["id"] in ids else next(
        (c["asset_id"] for c in clips if c["kind"] == "photo"), ids[0])
    mood = str(raw.get("music_mood") or "joyful").lower()
    return {
        "title": str(raw.get("title") or "Untitled cut")[:60],
        "why": str(raw.get("why") or "")[:200],
        "clips": clips,
        "music_mood": mood if mood in MOODS else "joyful",
        "caption_language": str(raw.get("caption_language") or "en"),
        "cover_asset_id": cover_id,
        "total_s": round(sum(clip_len(c) for c in clips), 2),
    }, notes


def _grammar_cut(raw: dict, clips: list[dict], rows: list[dict], beat: float, fast: bool, ctx: dict,
                 notes: list[str]) -> tuple[dict | None, list[str]]:
    """EDIT-GRAMMAR pass (grammar.enforce) + title/content consistency."""
    from . import grammar
    by_id = {r["id"]: r for r in rows}
    by_alias = {r["alias"]: r for r in rows}
    pool = [r for r in rows if usable(r)]
    retitled: list[str] = []
    title = str(raw.get("title") or "")[:60]
    clips = grammar.enforce(clips, by_id, pool, destination=ctx["destination"], prompt=ctx.get("prompt", ""),
                            language=ctx.get("language") or "en", beat=beat, make_clip=make_clip, snap=snap,
                            title=title, fast=fast, notes=notes, album_name=ctx.get("album_name", ""),
                            retitled=retitled)
    if len(clips) < 3:
        return None, notes + ["too few clips after grammar"]
    if retitled:
        title = retitled[-1]
    ids = [c["asset_id"] for c in clips]
    cover = raw.get("cover_asset_id")
    cover_row = by_alias.get(str(cover)) or by_id.get(str(cover))
    cover_id = cover_row["id"] if cover_row and cover_row["id"] in ids else ids[-1]
    mood = str(raw.get("music_mood") or "joyful").lower()
    return {
        "title": title or "Untitled cut",
        "why": str(raw.get("why") or "")[:200],
        "clips": clips,
        "music_mood": mood if mood in MOODS else "joyful",
        "caption_language": str(raw.get("caption_language") or ctx.get("language") or "en"),
        "cover_asset_id": cover_id,
        "total_s": round(sum(clip_len(c) for c in clips), 2),
        "destination": ctx["destination"],
    }, notes


def validate_edl(raw: Any, rows: list[dict], destination: str, beat: float,
                 ctx: dict | None = None) -> tuple[list[dict], list[str]]:
    """Validate model EDL into exactly 2 cuts. Missing/invalid cuts are filled from the fallback plan.
    ctx = {"prompt", "language", "album_name"} turns on the EDIT-GRAMMAR pass."""
    dest = DESTINATIONS.get(destination, DESTINATIONS["wa_status"])
    if ctx is not None:
        ctx = {**ctx, "destination": destination}
    notes: list[str] = []
    cuts_raw = raw.get("cuts") if isinstance(raw, dict) else raw if isinstance(raw, list) else None
    cuts: list[dict] = []
    for cr in (cuts_raw or [])[:4]:
        if not isinstance(cr, dict):
            continue
        cut, n = validate_cut(cr, rows, dest, beat, pace_max=(1.8 if cuts else None), ctx=ctx)
        notes += n
        if cut is None:
            continue
        if cuts and _same(cuts[0], cut):
            notes.append("dropped cut identical to the first")
            continue
        cut["source"] = "director"
        cuts.append(cut)
        if len(cuts) == 2:
            break
    if len(cuts) < 2:
        fb = fallback_plan(rows, destination, beat, ctx)
        for f in fb:
            if len(cuts) >= 2:
                break
            if cuts and _same(cuts[0], f):
                continue
            cuts.append(f)
        notes.append(f"filled {2 - len([c for c in cuts if c.get('source') == 'director'])} cut(s) from fallback")
    return cuts[:2], notes


def _same(a: dict, b: dict) -> bool:
    ia = [c["asset_id"] for c in a["clips"]]
    ib = [c["asset_id"] for c in b["clips"]]
    if ia == ib:
        return True
    inter = len(set(ia) & set(ib))
    return inter / max(1, min(len(ia), len(ib))) > 0.9 and ia[:3] == ib[:3]


# ---------------------------------------------------------------- fallback

def fallback_plan(rows: list[dict], destination: str, beat: float, ctx: dict | None = None) -> list[dict]:
    """Deterministic plan: (1) chronological story of the best shots, (2) top shots on the beat."""
    if ctx is not None:
        from . import grammar
        ctx = {**ctx, "destination": destination}
        topics = grammar.topics_in(ctx.get("prompt", ""))
        subject = grammar.parse_intent(ctx.get("prompt", ""))["subject"]
        good = sorted([r for r in rows if usable(r)], key=lambda r: -grammar.shot_value(r, topics, subject))
        hing = (ctx.get("language") or "en") in ("hinglish", "hi")
        out = []
        for k, (title, fast, mood) in enumerate([("Din ki kahaani" if hing else "The day in order", False, "emotional"),
                                                  ("Best moments", True, "joyful")]):
            seed = good[k::2][:8] or good[:8]
            raw = {"title": title, "clips": [{"asset_id": r["alias"], "hold_s": 2.0} for r in seed], "music_mood": mood}
            cut, _ = validate_cut(raw, rows, DESTINATIONS.get(destination, DESTINATIONS["wa_status"]), beat,
                                  pace_max=1.8 if fast else None, ctx=ctx)
            if cut:
                cut["why"] = "auto: grammar-ranked shots"
                cut["source"] = "auto"
                out.append(cut)
        if len(out) == 2:
            return out
    dest = DESTINATIONS.get(destination, DESTINATIONS["wa_status"])
    by_id = {r["id"]: r for r in rows}
    good = [r for r in rows if usable(r)] or list(rows)
    q = lambda r: int((r.get("analysis") or {}).get("quality", 5))  # noqa: E731

    def pick(ordered: list[dict], hold_beats: int, target: float) -> list[dict]:
        clips: list[dict] = []
        seen: list[dict] = []
        for r in ordered:
            if sum(clip_len(c) for c in clips) >= target:
                break
            if any(near_duplicate(r, s) for s in seen):
                continue
            bw = (r.get("analysis") or {}).get("best_window") or [0, 0]
            st = float(bw[0]) if bw[1] > bw[0] else 0.5
            c = make_clip(r, beat, hold_s=hold_beats * beat, in_s=st if r["type"] == "VIDEO" else 0,
                          out_s=st + max(2.0, hold_beats * beat * 1.4))
            if c:
                clips.append(c)
                seen.append(r)
        return clips

    best = sorted(good, key=lambda r: (-q(r), r.get("time") or ""))
    n_story = max(4, min(12, int(dest["target"] / max(beat * 4, 1.5))))
    story_set = sorted(best[: n_story + 2], key=lambda r: r.get("time") or "")
    c1 = pick(story_set, 4, dest["target"])
    c1 = fit_length(c1, by_id, dest, beat, best)
    used1 = {c["asset_id"] for c in c1}
    groups_first = sorted(good, key=lambda r: (r["id"] in used1, not (r.get("analysis") or {}).get("is_group"), -q(r)))
    hb = max(1, round(1.0 / beat))
    c2 = pick(groups_first, hb, dest["target"])
    c2 = fit_length(c2, by_id, dest, beat, [r for r in best if r["id"] not in used1] + best, 1.8)
    c1 = finish_cut(c1, by_id, "The night in order", [])
    c2 = finish_cut(c2, by_id, "Best moments", [])

    def cut(title: str, why: str, clips: list[dict], mood: str) -> dict:
        return {"title": title, "why": why, "clips": clips, "music_mood": mood, "caption_language": "en",
                "cover_asset_id": next((c["asset_id"] for c in clips if c["kind"] == "photo"), clips[0]["asset_id"] if clips else None),
                "total_s": round(sum(clip_len(c) for c in clips), 2), "source": "auto"}

    return [cut("The night in order", "auto: the best shots, in the order they happened", c1, "emotional"),
            cut("Best moments", "auto: the strongest shots and group photos, cut on the beat", c2, "joyful")]


# ---------------------------------------------------------------- main entry

def beat_track(prompt: str) -> dict | None:
    """The track whose beat grid the cuts are snapped to (so cuts land on ITS beats)."""
    p = prompt or ""
    if re.search(r"hackathon|hack|recap|event|build|coding|developer|energetic|tech", p, re.I):
        dev = next((t for t in tracks() if t.get("mood") in ("dev", "hacker") or
                    set(t.get("moods") or []) & {"dev", "hacker"}), None)
        if dev:
            return dev
    if re.search(r"emotion|bhav|dil|yaad|miss", p, re.I) and not re.search(r"energetic|hype|fun|masti", p, re.I):
        mood = "emotional"
    elif re.search(r"energetic|hype|fun|masti|recap|party|highlight|fast", p, re.I):
        t = next((t for t in tracks() if t.get("title") == "Life of Riley"), None)
        if t:
            return t
        mood = "joyful"
    else:
        mood = "joyful"
    return pick_track(mood)


def assign_music(cuts: list[dict], track: dict | None = None) -> None:
    """All cuts use the beat track when given: holds were snapped to its beat interval."""
    used: set[str] = set()
    for c in cuts:
        t = track or pick_track(c["music_mood"], used)
        if t:
            used.add(t["file"])
            c["music"] = {k: t.get(k) for k in ("file", "title", "bpm", "beat_offset", "attribution", "licence", "path")}


def detect_language(prompt: str) -> str:
    if re.search(r"[ऀ-ॿ]", prompt or ""):
        return "hi"
    hinglish = {"ke", "ki", "ka", "liye", "wali", "wala", "thoda", "bahut", "aur", "hai", "mein", "sab", "yaar", "acha", "accha", "dikhao", "banao"}
    words = set(re.findall(r"[a-z]+", (prompt or "").lower()))
    return "hinglish" if len(words & hinglish) >= 2 else "en"


async def plan(sarvam, rows: list[dict], prompt: str, destination: str, member: str | None = None,
               language: str | None = None, album_name: str = "") -> tuple[list[dict], dict]:
    """Single-shot director. Returns (cuts, info) where info has notes/label/raw."""
    btrack = beat_track(prompt)
    beat = beat_interval(btrack)
    language = language or detect_language(prompt)
    system = SYSTEM_PROMPT
    user = user_prompt(prompt, destination, member, language, rows, beat, album_name)
    info: dict[str, Any] = {"strategy": "single_shot", "attempts": 0, "notes": []}
    for attempt in range(2):
        info["attempts"] += 1
        try:
            data, _raw = await sarvam.plan_edit(system, user if attempt == 0 else user + "\nIMPORTANT: reply with valid JSON only.")
            cuts, notes = validate_edl(data, rows, destination, beat,
                                       ctx={"prompt": prompt, "language": language, "album_name": album_name})
            info["notes"] = notes
            info["label"] = "director" if any(c.get("source") == "director" for c in cuts) else "auto"
            if info["label"] == "director":
                break
        except Exception as e:  # invalid JSON, API error
            log.warning("plan attempt %d failed: %s", attempt + 1, e)
            info["notes"].append(f"attempt {attempt + 1} failed: {type(e).__name__}: {str(e)[:120]}")
            cuts = []
    if not cuts:
        cuts = fallback_plan(rows, destination, beat, {"prompt": prompt, "language": language, "album_name": album_name})
        info["label"] = "auto"
    assign_music(cuts, btrack)
    info["beat_s"] = round(beat, 3)
    info["language"] = language
    return cuts, info
