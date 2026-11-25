"""Invitation card -> structured event (Sarvam Document AI) -> shot list (sarvam-105b).

extract_invite(): job-based Doc AI extract (~10 s), normalised to
  {event_name, event_type, hosts[], family_names[], venue, ceremonies:[{name, name_en, date, time}], language}
shot_list(): [{id, label_en, label_local, why, ceremony}] for the event.
process_invite(): both, cached by image hash.
"""
from __future__ import annotations

import difflib
import io
import logging
import re
from typing import Any

from PIL import Image, ImageOps, UnidentifiedImageError

from .extras_common import (ExtrasInputError, Timings, as_str, as_str_list, cache_get, cache_put, chat_json,
                            sha)
from .sarvam import SarvamClient

log = logging.getLogger("memories.invite")

DOC_LANGS = {"hi-IN", "en-IN", "bn-IN", "gu-IN", "kn-IN", "ml-IN", "mr-IN", "od-IN", "pa-IN", "ta-IN", "te-IN",
             "ur-IN", "as-IN", "sa-IN", "ne-IN"}
MAX_IMAGE_BYTES = 15_000_000
MAX_SIDE = 2200

INVITE_DOC_SCHEMA = {
    "type": "object",
    "properties": {
        "event_name": {"type": "string", "description": "Name of the event, e.g. 'Rahul weds Priya', 'Diwali Milan', 'Griha Pravesh'"},
        "event_type": {"type": "string", "description": "One English word or two: wedding, engagement, diwali, holi, birthday, griha pravesh, mundan, puja, anniversary, other"},
        "hosts": {"type": "array", "items": {"type": "string"}, "description": "Names of the people inviting (parents / hosts), as printed"},
        "family_names": {"type": "array", "items": {"type": "string"}, "description": "Every other person named on the card: couple, children, elders (Dadi, Nani...), relatives, as printed"},
        "venue": {"type": "string", "description": "Venue name, address and city"},
        "ceremonies": {"type": "array", "description": "Each ceremony / function listed, in order", "items": {
            "type": "object", "properties": {
                "name": {"type": "string", "description": "Ceremony name as printed"},
                "name_en": {"type": "string", "description": "Ceremony name in English (e.g. Haldi, Mehendi, Sangeet, Baraat, Pheras, Reception, Lakshmi Puja)"},
                "date": {"type": "string", "description": "Date in YYYY-MM-DD"},
                "time": {"type": "string", "description": "Time in 24h HH:MM"}}}},
        "language": {"type": "string", "description": "Main language of the card as a code: hi-IN, en-IN, mr-IN, gu-IN, bn-IN, ta-IN, te-IN, kn-IN, ml-IN, pa-IN, od-IN"},
    },
}

SHOT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["shots"],
    "properties": {"shots": {"type": "array", "items": {
        "type": "object", "additionalProperties": False,
        "required": ["id", "label_en", "label_local", "why", "ceremony"],
        "properties": {
            "id": {"type": "string"}, "label_en": {"type": "string"}, "label_local": {"type": "string"},
            "why": {"type": "string"}, "ceremony": {"type": "string"}}}}},
}

SHOT_SYSTEM = """You are a family-event photo director in India. From an event invitation you write the SHOT LIST that
family members should capture on their phones so an editor can cut two warm reels (a 15-30 s WhatsApp status and an
Instagram reel). Be concrete and culturally specific: e.g. Haldi -> turmeric on the bride's face, elders applying haldi;
Mehendi -> close-up of the mehendi design, bride's hands with the groom's name; Diwali -> rangoli, rows of diyas, Lakshmi
puja aarti, phuljhadi sparklers at night, full family group photo. Include the named elders (Dadi, Nani...) and hosts in
specific shots when the card names them. Cover every ceremony, plus 2-3 general shots (arrivals, venue decor, group).
Return JSON {"shots": [...]} with 8-14 items, each:
- id: short snake_case slug, unique (e.g. "haldi_bride_face")
- label_en: what to shoot, max 8 words, English
- label_local: the same label in the card's language and script (Devanagari for Hindi); English if the card is English
- why: one short sentence on why this shot matters for the reel
- ceremony: the ceremony's English name from the card, or "general"."""

_DEV_DIGITS = str.maketrans("०१२३४५६७८९", "0123456789")
_MONTHS = {m: i for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}
_HI_MONTHS = {"जनवरी": 1, "फरवरी": 2, "फ़रवरी": 2, "मार्च": 3, "अप्रैल": 4, "मई": 5, "जून": 6, "जुलाई": 7,
              "अगस्त": 8, "सितंबर": 9, "सितम्बर": 9, "अक्टूबर": 10, "नवंबर": 11, "नवम्बर": 11, "दिसंबर": 12,
              "दिसम्बर": 12}


# ---------------------------------------------------------------- normalisation (pure)

def normalize_date(s: Any) -> str:
    """Best effort -> YYYY-MM-DD; returns the cleaned input if it can't be parsed."""
    raw = as_str(s, 60)
    t = raw.translate(_DEV_DIGITS).strip()
    if not t:
        return ""
    m = re.search(r"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})", t)
    if m:
        y, mo, d = int(m[1]), int(m[2]), int(m[3])
        return _ymd(y, mo, d) or raw
    m = re.search(r"(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})", t)
    if m:  # Indian order: DD/MM/YYYY
        d, mo, y = int(m[1]), int(m[2]), int(m[3])
        return _ymd(y + 2000 if y < 100 else y, mo, d) or raw
    low = t.lower()
    mo = None
    for name, num in _HI_MONTHS.items():
        if name in t:
            mo = num
    if mo is None:
        m2 = re.search(r"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b", low)
        if m2:
            mo = _MONTHS[m2[1]]
    if mo is not None:
        nums = [int(x) for x in re.findall(r"\d+", t)]
        y = next((n for n in nums if n >= 1900), None)
        d = next((n for n in nums if 1 <= n <= 31), None)
        if y and d:
            return _ymd(y, mo, d) or raw
    return raw


def _ymd(y: int, mo: int, d: int) -> str | None:
    if 1900 <= y <= 2100 and 1 <= mo <= 12 and 1 <= d <= 31:
        return f"{y:04d}-{mo:02d}-{d:02d}"
    return None


def normalize_time(s: Any) -> str:
    """Best effort -> HH:MM (24h). Handles '7:30 PM', '19.30', 'सायं 7 बजे', '7 baje shaam'."""
    raw = as_str(s, 40)
    t = raw.translate(_DEV_DIGITS).lower()
    if not t:
        return ""
    m = re.search(r"(\d{1,2})(?:[:.](\d{2}))?", t)
    if not m:
        return raw
    h, mi = int(m[1]), int(m[2] or 0)
    am = bool(re.search(r"\ba\.?\s?m\b|प्रातः|प्रात|सुबह|subah|morning", t))
    # "प्रातः" contains "रात", so strip the morning words before looking for evening/night ones
    t_pm = re.sub(r"प्रातः|प्रात", " ", t)
    pm = not am and bool(re.search(r"\bp\.?\s?m\b|सायं|शाम|रात्रि|रात|दोपहर|shaam|raat|evening|night", t_pm))
    if pm and h < 12:
        h += 12
    if am and h == 12:
        h = 0
    if 0 <= h <= 23 and 0 <= mi <= 59:
        return f"{h:02d}:{mi:02d}"
    return raw


def guess_language(text: str, default: str = "hi-IN") -> str:
    """Script-based guess used when the model leaves language empty or invalid."""
    ranges = [("hi-IN", 0x0900, 0x097F), ("bn-IN", 0x0980, 0x09FF), ("pa-IN", 0x0A00, 0x0A7F),
              ("gu-IN", 0x0A80, 0x0AFF), ("od-IN", 0x0B00, 0x0B7F), ("ta-IN", 0x0B80, 0x0BFF),
              ("te-IN", 0x0C00, 0x0C7F), ("kn-IN", 0x0C80, 0x0CFF), ("ml-IN", 0x0D00, 0x0D7F)]
    counts = {code: 0 for code, _, _ in ranges}
    latin = 0
    for ch in text:
        o = ord(ch)
        if ch.isascii() and ch.isalpha():
            latin += 1
            continue
        for code, a, b in ranges:
            if a <= o <= b:
                counts[code] += 1
    best = max(counts, key=counts.get)
    if counts[best] == 0:
        return "en-IN" if latin else default
    return best


def normalize_invite(raw: Any, default_language: str = "hi-IN") -> dict:
    """Coerce Doc AI output into the stable invite shape. Never raises."""
    d = raw if isinstance(raw, dict) else {}
    # Doc AI sometimes nests the payload one level down
    for k in ("result", "data", "extracted", "output"):
        if isinstance(d.get(k), dict) and not d.get("ceremonies") and not d.get("event_name"):
            d = d[k]
    cers = []
    raw_cers = d.get("ceremonies")
    for c in raw_cers if isinstance(raw_cers, list) else []:
        if isinstance(c, str):
            c = {"name": c}
        if not isinstance(c, dict):
            continue
        name = as_str(c.get("name") or c.get("name_en"), 80)
        name_en = as_str(c.get("name_en") or c.get("name"), 80)
        if not (name or name_en):
            continue
        cers.append({"name": name, "name_en": name_en, "date": normalize_date(c.get("date")),
                     "time": normalize_time(c.get("time"))})
    hosts = as_str_list(d.get("hosts"))
    fam = [n for n in as_str_list(d.get("family_names") or d.get("names") or d.get("family_elders"))
           if n.lower() not in {h.lower() for h in hosts}]
    lang = as_str(d.get("language"), 10)
    if lang not in DOC_LANGS:
        alias = {"hindi": "hi-IN", "english": "en-IN", "hi": "hi-IN", "en": "en-IN", "marathi": "mr-IN",
                 "gujarati": "gu-IN", "bengali": "bn-IN", "tamil": "ta-IN", "telugu": "te-IN",
                 "kannada": "kn-IN", "malayalam": "ml-IN", "punjabi": "pa-IN", "odia": "od-IN"}
        sample = " ".join([as_str(d.get("event_name")), *hosts, *fam, *(c["name"] for c in cers)])
        lang = alias.get(lang.lower()) or guess_language(sample, default_language)
    return {
        "event_name": as_str(d.get("event_name"), 160),
        "event_type": as_str(d.get("event_type"), 40).lower(),
        "hosts": hosts,
        "family_names": fam,
        "venue": as_str(d.get("venue"), 300),
        "ceremonies": cers,
        "language": lang,
    }


def _slug(s: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")
    return s[:48] or "shot"


def normalize_shot_list(raw: Any, invite: dict | None = None, limit: int = 16) -> list[dict]:
    items = raw.get("shots") if isinstance(raw, dict) else raw
    if not isinstance(items, list):
        return []
    known = {}
    for c in (invite or {}).get("ceremonies") or []:
        for k in (c.get("name_en"), c.get("name")):
            if k:
                known[k.lower()] = c.get("name_en") or c.get("name")
    out: list[dict] = []
    seen: set[str] = set()
    for it in items:
        if not isinstance(it, dict):
            continue
        label_en = as_str(it.get("label_en") or it.get("label"), 120)
        if not label_en:
            continue
        sid = _slug(as_str(it.get("id")) or label_en)
        base, n = sid, 2
        while sid in seen:
            sid, n = f"{base}_{n}", n + 1
        seen.add(sid)
        cer = as_str(it.get("ceremony"), 80) or "general"
        if cer.lower() in known:
            cer = known[cer.lower()]
        elif cer.lower() != "general" and known:  # snap model typos ("Sangeit") to the card's ceremony
            close = difflib.get_close_matches(cer.lower(), list(known), n=1, cutoff=0.75)
            cer = known[close[0]] if close else cer
        out.append({"id": sid, "label_en": label_en, "label_local": as_str(it.get("label_local"), 160) or label_en,
                    "why": as_str(it.get("why"), 240), "ceremony": cer})
        if len(out) >= limit:
            break
    return out


# ---------------------------------------------------------------- image prep

def prepare_image(data: bytes) -> bytes:
    """Validate + EXIF-rotate + downscale to a JPEG Doc AI accepts. Raises ExtrasInputError."""
    if not data:
        raise ExtrasInputError("empty image")
    if len(data) > MAX_IMAGE_BYTES:
        raise ExtrasInputError("image over 15 MB", 413)
    try:
        im = Image.open(io.BytesIO(data))
        im = ImageOps.exif_transpose(im)
    except (UnidentifiedImageError, OSError) as e:
        raise ExtrasInputError(f"not a readable image ({type(e).__name__}); send JPEG/PNG/WebP", 415)
    if im.mode not in ("RGB", "L"):
        bg = Image.new("RGB", im.size, "white")
        im = im.convert("RGBA")
        bg.paste(im, mask=im.split()[-1])
        im = bg
    im = im.convert("RGB")
    if max(im.size) > MAX_SIDE:
        im.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=90)
    return buf.getvalue()


# ---------------------------------------------------------------- Sarvam calls

async def extract_invite(client: SarvamClient, image: bytes, *, language: str = "hi-IN",
                         timings: Timings | None = None) -> dict:
    timings = timings or Timings()
    if language not in DOC_LANGS:
        raise ExtrasInputError(f"unsupported language {language!r}")
    with timings.span("prepare_image"):
        jpeg = prepare_image(image)
    with timings.span("docai_extract"):
        raw = await client.doc_extract(jpeg, "image/jpeg", "invite.jpg", INVITE_DOC_SCHEMA, language=language,
                                       timeout_s=75)
    return normalize_invite(raw, language)


async def shot_list(client: SarvamClient, invite: dict, *, timings: Timings | None = None) -> list[dict]:
    timings = timings or Timings()
    import json
    user = ("Invitation (extracted):\n" + json.dumps(invite, ensure_ascii=False, indent=1) +
            "\nWrite the shot list now.")
    with timings.span("shot_list_llm"):
        raw = await chat_json(client, SHOT_SYSTEM, user, SHOT_SCHEMA, "shot_list", reasoning_effort="low",
                              max_tokens=5000)
    shots = normalize_shot_list(raw, invite)
    if not shots:
        from .sarvam import SarvamError
        raise SarvamError("shot_list: model returned no shots")
    return shots


async def process_invite(client: SarvamClient, image: bytes, *, language: str = "hi-IN",
                         use_cache: bool = True) -> dict:
    """Full flow with an image-hash cache. Returns {invite, shot_list, timings_ms, cached, image_sha}."""
    t = Timings()
    key = sha(image) + "_" + language
    if use_cache:
        hit = cache_get("invite", key)
        if hit and hit.get("shot_list"):
            return {**hit, "cached": True, "timings_ms": {"cache": 0, **t.total()}}
    inv = await extract_invite(client, image, language=language, timings=t)
    shots = await shot_list(client, inv, timings=t)
    out = {"invite": inv, "shot_list": shots, "image_sha": key.split("_")[0]}
    cache_put("invite", key, out)
    return {**out, "cached": False, "timings_ms": t.total()}
