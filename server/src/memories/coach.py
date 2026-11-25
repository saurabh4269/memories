"""Shot coach: event shot list (sarvam-105b, cached) + album coverage (Immich smart search, people) -> missing-shot cards."""
from __future__ import annotations

import asyncio
import itertools
import logging
import re
import time
from typing import Any

from . import db, flags
from .analysis import load_rows
from .immich import ImmichClient
from .sarvam import SarvamClient, parse_json_tolerant

log = logging.getLogger("memories.coach")

SHOTLIST_SYSTEM = """You plan the must-have shots for an Indian family event album. Given the event name/description (and optional invite details), return JSON only:
{"occasion":"diwali|wedding|conference|birthday|other","shots":[{"id":"rangoli","label":"Rangoli before guests walk on it","query":"rangoli on the floor","keywords":["rangoli","kolam"],"tip":"Shoot from above, fill the frame, early before it gets smudged"}]}
Give 6-10 shots in rough chronological order. query is a short English phrase for CLIP image search. keywords are lowercase words that would appear in a caption of such a photo. tip is one short framing/pose tip."""

DEFAULT_SHOTS = {
    "diwali": [
        ("rangoli", "Rangoli, before guests walk on it", "colorful rangoli on the floor", ["rangoli", "kolam"], "Shoot straight down from a chair, fill the frame"),
        ("diyas", "Diyas being lit", "lit oil lamps diyas", ["diya", "diyas", "lamp", "candle"], "Get low, close to the flame; let the background go dark"),
        ("aarti", "Lakshmi puja aarti", "aarti puja ceremony", ["aarti", "puja", "prayer", "worship"], "Stand to the side, catch faces lit by the aarti thali"),
        ("sweets", "Mithai and the dinner spread", "indian sweets mithai plate", ["sweet", "sweets", "mithai", "food", "dessert"], "Top-down or 45°, one hand reaching in"),
        ("phuljhadi", "Phuljhadi and fireworks", "sparklers fireworks night", ["sparkler", "firework", "fireworks", "phuljhadi"], "Hold still, shoot a short video, faces lit by sparks"),
        ("family", "The whole family together", "large family group photo", ["group", "family"], "Elders seated in front, kids on laps, phone at eye level, 3s timer"),
    ],
}


HACKATHON_RE = re.compile(r"hack|buildathon|ideathon|devfest", re.I)
HACKATHON_SPONSORS = ["Flagsmith", "NudgeBee", "Sarvam"]  # Festive Hacks 2026; event_context["sponsors"] overrides
# id, label, CLIP query, framing tip (ordered by importance for the team's reel)
HACKATHON_SHOTS = [
    ("team_group", "Your team's group photo", "team posing together for a group photo",
     "Whole team shoulder to shoulder with the laptops or event banner behind, phone at eye level, 3 s timer"),
    ("demo_stage", "Your team demoing on stage", "people presenting a demo on stage",
     "Shoot from the front row side angle: presenter plus the screen in one frame, burst during the demo"),
    ("sponsor_booth", "The team at a sponsor booth ({sponsors})", "group of people at a sponsor booth",
     "Stand the team beside the booth logo, step back so the brand name is readable, everyone looking in"),
    ("late_night", "Late-night coding", "developers coding late at night",
     "Low light: let screen glow light the faces, hold the phone steady against the table, no flash"),
    ("prize", "Prize or closing moment", "hackathon winners receiving a prize on stage",
     "Get close to the stage early, shoot a short video of the name being announced"),
    ("food", "Food and chai break", "people eating snacks and drinking chai",
     "Candid from the side while the team laughs over food, 45 degrees, no posing"),
]
_CODING = {"coding_closeup", "team_working_at_laptops"}


def _hour(t: str | None) -> int | None:
    m = re.match(r"\d{4}-\d\d-\d\dT(\d\d)", t or "")
    return int(m.group(1)) if m else None


def hackathon_matches(rows: list[dict], sponsors: list[str]) -> dict[str, list[str]]:
    """Which album rows already cover each hackathon shot (analysis activity/caption + team faces + time)."""
    sp = re.compile("|".join(re.escape(x) for x in sponsors), re.I) if sponsors else None
    out: dict[str, list[str]] = {s[0]: [] for s in HACKATHON_SHOTS}
    for r in rows:
        an = r.get("analysis") or {}
        act = an.get("activity") or ""
        cap = " ".join(str(an.get(k) or "") for k in ("caption", "moment_tag", "scene", "main_subjects")).lower()
        tf = int(r.get("team_faces") or 0)
        h = _hour(r.get("time"))
        if act in ("team_group_pose", "selfie") or (tf >= 2 and re.search(r"pos(e|ing)|selfie|group photo|smil\w* at the camera", cap)):
            out["team_group"].append(r["id"])
        if (act == "stage_talk" or "stage" in cap) and (tf >= 1 or re.search(r"\bdemo|pitch|judg|their project|prototype", cap)):
            out["demo_stage"].append(r["id"])
        if (act == "booth_or_sponsor" or "booth" in cap) and ((tf >= 1 and sp is not None and sp.search(cap)) or tf >= 2):
            out["sponsor_booth"].append(r["id"])
        if (act in _CODING or an.get("team_work")) and h is not None and (h >= 22 or h < 5):
            out["late_night"].append(r["id"])
        if re.search(r"prize|award|winner|trophy|certificate|cheque", cap):
            out["prize"].append(r["id"])
        if re.search(r"pizza|food|chai|coffee|snack|eating|dinner|lunch|meal", cap):
            out["food"].append(r["id"])
    return out


def _lang_code(lang: str) -> str:
    return lang if "-" in lang else f"{lang}-IN"


async def _translate_cached(sarvam: SarvamClient, text: str, lang: str) -> str:
    key = f"{lang}|{text}"
    hit = db.kv_get("coach_tr", key)
    if hit:
        return hit
    out = await sarvam.translate(text, _lang_code(lang), source="en-IN")
    if out and out != text:
        db.kv_put("coach_tr", key, out)
    return out


def member_profile(member: str | None, album_id: str | None = None) -> dict:
    """Traits of a member who joined via QR (join_api's join_redemptions table): language, role."""
    if not member:
        return {}
    try:
        with db._lock:
            row = db.conn().execute(
                "SELECT language, role FROM join_redemptions WHERE name_key=? OR member_id=? "
                "ORDER BY (album_id=?) DESC, created_at DESC LIMIT 1",
                (member.strip().casefold(), member, album_id or "")).fetchone()
    except Exception:  # table not created yet (no joins)
        return {}
    return {k: v for k, v in zip(("language", "role"), row or ()) if v}


async def shot_list(sarvam: SarvamClient, immich: ImmichClient, album_id: str) -> dict:
    cached = db.kv_get("shotlist", album_id)
    if cached and cached.get("occasion") == "hackathon":
        return cached
    try:
        album = await immich.get_album(album_id)
    except Exception:
        album = {}
    ctx = db.kv_get("event_context", album_id) or {}
    if HACKATHON_RE.search(f"{album.get('albumName', '')} {album.get('description', '')} {ctx}"):
        sponsors = [str(x) for x in (ctx.get("sponsors") if isinstance(ctx, dict) else None) or HACKATHON_SPONSORS]
        res = {"occasion": "hackathon", "source": "curated:hackathon", "sponsors": sponsors, "shots": [
            {"id": i, "label": l.format(sponsors=", ".join(sponsors)), "query": q, "tip": t}
            for i, l, q, t in HACKATHON_SHOTS]}
        db.kv_put("shotlist", album_id, res)
        return res
    if cached:
        return cached
    user = (f"Event name: {album.get('albumName', '')}\nDescription: {album.get('description', '')}\n"
            f"Invite details: {ctx or '-'}")
    try:
        data, _ = await sarvam.plan_edit(SHOTLIST_SYSTEM, user, max_tokens=3000)
        shots = [s for s in data.get("shots", []) if isinstance(s, dict) and s.get("query")]
        if len(shots) < 3:
            raise ValueError("too few shots")
        res = {"occasion": data.get("occasion", "other"), "shots": shots, "source": "sarvam-105b"}
    except Exception as e:
        log.warning("shot list generation failed (%s); using Diwali defaults", e)
        res = {"occasion": "diwali", "source": "default", "shots": [
            {"id": i, "label": l, "query": q, "keywords": k, "tip": t} for i, l, q, k, t in DEFAULT_SHOTS["diwali"]]}
    db.kv_put("shotlist", album_id, res)
    return res


def _covered_by_analysis(rows: list[dict], keywords: list[str], ids: set[str] | None = None) -> int:
    kws = [k.lower() for k in keywords if k]
    n = 0
    for r in rows:
        if ids is not None and r["id"] not in ids:
            continue
        an = r.get("analysis") or {}
        text = " ".join(str(an.get(k, "")) for k in ("caption", "scene", "moment_tag")).lower()
        if any(re.search(r"\b" + re.escape(k), text) for k in kws):
            n += 1
    return n


_result_cache: dict[str, tuple[float, dict]] = {}
RESULT_TTL_S = 120


async def coach_cards(sarvam: SarvamClient, immich: ImmichClient, album_id: str, member: str | None = None,
                      lang: str | None = None, traits: dict | None = None) -> dict:
    tr = member_profile(member, album_id)
    tr.update({k: v for k, v in (traits or {}).items() if v})
    lang = lang or (tr.get("language") or "").split("-")[0] or None
    fl = await asyncio.to_thread(flags.identity_flags, member or "anonymous", tr or None)
    lite = flags.ml_lite(fl)
    sc = fl.get("shot_coach", {})
    max_cards = 3
    if isinstance(sc.get("value"), dict):
        max_cards = int(sc["value"].get("max_cards", 3))
    cache_key = f"{album_id}|{member}|{lang}"
    base = {"mode": flags.mode(fl), "album_id": album_id}
    if not sc.get("enabled", True) or (lite is not None and lite.get("shot_coach") is False):
        cached = db.kv_get("coach", cache_key)
        return {**base, "cards": (cached or {}).get("cards", [])[:max_cards], "cached": bool(cached),
                "disabled": True, "traits": tr}
    t0 = time.perf_counter()
    rkey = f"{album_id}|{lang}|{max_cards}"
    hit = _result_cache.get(rkey)
    if hit and time.time() - hit[0] < RESULT_TTL_S:
        return {**hit[1], **base, "traits": tr, "cached": True, "ms": round((time.perf_counter() - t0) * 1000)}
    sl = await shot_list(sarvam, immich, album_id)
    rows = await load_rows(immich, album_id)
    if sl.get("occasion") == "hackathon":
        out = await _hackathon_cards(sarvam, immich, album_id, rows, sl, lang, max_cards)
        out = {**base, **out, "traits": tr, "ms": round((time.perf_counter() - t0) * 1000)}
        _result_cache[rkey] = (time.time(), out)
        db.kv_put("coach", cache_key, out)
        return out
    cards: list[dict] = []

    async def check(shot: dict) -> dict | None:
        hits_ids: set[str] = set()
        try:
            hits = await immich.smart_search(shot["query"], album_id, size=5)
            hits_ids = {h["id"] for h in hits}
        except Exception:
            pass
        kws = shot.get("keywords") or [shot.get("id", "")]
        n_top = _covered_by_analysis(rows, kws, hits_ids) if hits_ids else 0
        n_all = _covered_by_analysis(rows, kws)
        if n_top or n_all:
            return None
        return {"kind": "moment", "id": shot.get("id"), "title": f"Missing: {shot.get('label')}",
                "tip": shot.get("tip", ""), "priority": 2}

    smart = sl["shots"] if (lite or {}).get("smart_search") != "cached" else []
    res = await asyncio.gather(*(check(s) for s in smart))
    cards += [c for c in res if c]
    if (lite or {}).get("smart_search") == "cached":
        for s in sl["shots"]:
            if not _covered_by_analysis(rows, s.get("keywords") or [s.get("id", "")]):
                cards.append({"kind": "moment", "id": s.get("id"), "title": f"Missing: {s.get('label')}",
                              "tip": s.get("tip", ""), "priority": 2})
    # people coverage
    counts: dict[str, int] = {}
    together: set[frozenset] = set()
    for r in rows:
        names = sorted(set(r.get("people") or []))
        for n in names:
            counts[n] = counts.get(n, 0) + 1
        for a, b in itertools.combinations(names, 2):
            together.add(frozenset((a, b)))
    for n, c in sorted(counts.items(), key=lambda x: x[1]):
        if c <= 1:
            cards.append({"kind": "person", "id": f"person:{n}", "title": f"Only {c} photo of {n} so far",
                          "tip": f"Get a close portrait of {n}: eye level, window light, ask them to laugh", "priority": 1})
    top = [n for n, _ in sorted(counts.items(), key=lambda x: -x[1])[:4]]
    for a, b in itertools.combinations(top, 2):
        if frozenset((a, b)) not in together:
            cards.append({"kind": "pair", "id": f"pair:{a}+{b}", "title": f"No photo of {a} with {b} yet",
                          "tip": "Shoulder to shoulder, heads close, shoot a burst while they talk", "priority": 1})
            break
    cards.sort(key=lambda c: c["priority"])
    cards = cards[:max_cards]
    if lang and not lang.startswith("en"):
        async def tr(c):
            try:
                c["title"] = await _translate_cached(sarvam, c["title"], lang)
                c["tip"] = await _translate_cached(sarvam, c["tip"], lang)
            except Exception as e:
                log.warning("coach translate failed: %s", e)
        await asyncio.gather(*(tr(c) for c in cards))
    out = {**base, "cards": cards, "shot_list_source": sl.get("source"), "occasion": sl.get("occasion"),
           "ms": round((time.perf_counter() - t0) * 1000)}
    db.kv_put("coach", cache_key, out)
    return out


async def _hackathon_cards(sarvam: SarvamClient, immich: ImmichClient, album_id: str, rows: list[dict], sl: dict,
                           lang: str | None, max_cards: int) -> dict:
    for r in rows:
        if not r.get("analysis") and r.get("stale_analysis"):
            r["analysis"] = r["stale_analysis"]
    try:
        from .team import score_rows
        team_ids = score_rows(rows)
    except Exception as e:  # no team module: shots that need team faces just count as missing
        log.debug("team scoring unavailable: %s", e)
        team_ids = []
    matches = hackathon_matches(rows, sl.get("sponsors") or HACKATHON_SPONSORS)
    unanalysed = {r["id"] for r in rows if not r.get("analysis")}

    async def smart(shot: dict) -> list[str]:
        try:
            return [h["id"] for h in await immich.smart_search(shot["query"], album_id, size=5)]
        except Exception:
            return []

    hits = await asyncio.gather(*(smart(s) for s in sl["shots"]))
    cards, coverage = [], {}
    for prio, (shot, top) in enumerate(zip(sl["shots"], hits)):
        found = matches.get(shot["id"], [])
        # an un-analysed photo that CLIP ranks top for this shot may cover it: don't nag about it
        maybe = [i for i in top[:3] if i in unanalysed]
        coverage[shot["id"]] = {"found": len(found), "smart_unverified": len(maybe)}
        if found or maybe:
            continue
        cards.append({"kind": "moment", "id": shot["id"], "title": f"Missing: {shot['label']}", "tip": shot["tip"],
                      "label": shot["label"], "priority": prio, "query": shot["query"], "lang": "en"})
    cards = cards[:max_cards]
    if lang and not lang.startswith("en"):
        async def tr(c: dict) -> None:
            try:
                label, c["tip"], prefix = await asyncio.gather(
                    _translate_cached(sarvam, c["label"], lang), _translate_cached(sarvam, c["tip"], lang),
                    _translate_cached(sarvam, "Still missing", lang) if lang.split("-")[0] != "hi" else asyncio.sleep(0, "अभी बाकी"))
                c["title"], c["label"] = f"{prefix}: {label}", label
                c["lang"] = lang
            except Exception as e:
                log.warning("coach translate failed: %s", e)
        await asyncio.gather(*(tr(c) for c in cards))
    return {"cards": cards, "occasion": "hackathon", "shot_list_source": sl.get("source"), "coverage": coverage,
            "photos_checked": len(rows), "team_people": len(team_ids)}


INVITE_SCHEMA = {
    "type": "object",
    "properties": {
        "event_name": {"type": "string"},
        "names": {"type": "array", "items": {"type": "string"}, "description": "people named on the invite (hosts, couple, elders)"},
        "ceremonies": {"type": "array", "items": {"type": "object", "properties": {
            "name": {"type": "string"}, "name_en": {"type": "string"}, "date": {"type": "string"}, "time": {"type": "string"}}}},
        "venue": {"type": "string"},
    },
}


async def extract_invite(sarvam: SarvamClient, album_id: str, data: bytes, content_type: str, filename: str) -> dict:
    res = await sarvam.doc_extract(data, content_type, filename, INVITE_SCHEMA)
    db.kv_put("event_context", album_id, res)
    db.kv_put("shotlist", album_id, None)  # regenerate with the new context
    return res
