"""Voice prompt -> structured reel intent.

Primary: Sarvam Dictate POST /v2/dictate (vocabulary + context + output_rules) -> JSON intent in one call.
Fallback: saaras:v4 /speech-to-text (keyterms) -> sarvam-105b intent extraction.
Intent: {transcript, request, people[], include[], exclude[], mood, music, destination}
"""
from __future__ import annotations

import json
import logging
from pathlib import PurePath
from typing import Any

from .extras_common import ExtrasInputError, Timings, as_str, as_str_list, chat_json
from .sarvam import SarvamAuthError, SarvamClient, SarvamError, SarvamQuotaError, parse_json_tolerant

log = logging.getLogger("memories.dictate")

MAX_AUDIO_BYTES = 10_000_000  # Dictate hard limit (and 30 s)
STT_LANGS = {"hi-IN", "en-IN", "bn-IN", "gu-IN", "kn-IN", "ml-IN", "mr-IN", "od-IN", "pa-IN", "ta-IN", "te-IN"}

# extension / sniffed kind -> canonical MIME sent upstream
AUDIO_MIME = {
    "wav": "audio/wav", "mp3": "audio/mpeg", "m4a": "audio/mp4", "mp4": "audio/mp4", "aac": "audio/aac",
    "webm": "audio/webm", "ogg": "audio/ogg", "opus": "audio/ogg", "flac": "audio/flac", "amr": "audio/amr",
}
MIME_ALIASES = {
    "audio/x-wav": "wav", "audio/wav": "wav", "audio/wave": "wav", "audio/vnd.wave": "wav",
    "audio/mpeg": "mp3", "audio/mp3": "mp3",
    "audio/mp4": "m4a", "audio/m4a": "m4a", "audio/x-m4a": "m4a", "video/mp4": "m4a",
    "audio/aac": "aac", "audio/x-aac": "aac", "audio/aacp": "aac",
    "audio/webm": "webm", "video/webm": "webm",
    "audio/ogg": "ogg", "audio/opus": "ogg", "application/ogg": "ogg",
    "audio/flac": "flac", "audio/x-flac": "flac", "audio/amr": "amr",
}

# always-on vocabulary: (word, sounds_like, description)
BASE_VOCAB: list[tuple[str, list[str], str]] = [
    ("रील", ["व्हील"], "Instagram reel, a short vertical video"),
    ("reel", ["wheel"], "Instagram reel, a short vertical video"),
    ("स्टेटस", [], "WhatsApp status"),
    ("status", [], "WhatsApp status"),
    ("स्टोरी", [], "Instagram story"),
    ("story", [], "Instagram story"),
    ("WhatsApp", ["व्हाट्सएप", "वॉट्सऐप"], "messaging app"),
    ("Instagram", ["इंस्टाग्राम", "इंस्टा"], "social app"),
    ("Nani", ["नानी"], "maternal grandmother"),
    ("Dadi", ["दादी"], "paternal grandmother"),
    ("Nana", ["नाना"], "maternal grandfather"),
    ("Dada", ["दादा"], "paternal grandfather"),
    ("Mummy", ["मम्मी"], "mother"),
    ("Papa", ["पापा"], "father"),
    ("Chintu", ["चिंटू"], "family nickname"),
    ("bhaiya", ["भैया"], "elder brother"),
    ("didi", ["दीदी"], "elder sister"),
]
# Devanagari forms we canonicalise to the Latin nickname in the intent
CANON = {s: w for w, sl, _ in BASE_VOCAB[8:] for s in sl}

DESTINATIONS = {
    "status": "status", "whatsapp": "status", "whatsapp status": "status", "स्टेटस": "status",
    "reel": "reel", "reels": "reel", "instagram": "reel", "instagram reel": "reel", "insta": "reel", "रील": "reel",
    "story": "story", "stories": "story", "instagram story": "story", "स्टोरी": "story",
}

CONTEXT = ("A family member (often an elder, speaking Hindi, English or Hinglish) asks an app to make a short "
           "video reel from the shared family event album (Diwali, wedding, festival). They name family members "
           "(Nani, Dadi, Chintu...), moments to include or skip, a mood or song, and where it will be posted "
           "(WhatsApp status, Instagram reel or story). The word रील means reel, never wheel.")

OUTPUT_RULES = (
    'Return only one JSON object, no prose: {"request": <the request as one clear English sentence>, '
    '"people": [people or family nicknames mentioned, in Latin script, e.g. "Dadi", "Chintu", "kids"], '
    '"include": [moments/things wanted, short English phrases], "exclude": [things to avoid, short English phrases], '
    '"mood": <one English word or null>, "music": <music wish in English or null>, '
    '"destination": <"status" for WhatsApp status, "reel" for Instagram reel, "story" for Instagram story, or null>}. '
    "Write null when it was not said.")

INTENT_SCHEMA = {
    "type": "object", "additionalProperties": False,
    "required": ["request", "people", "include", "exclude", "mood", "music", "destination"],
    "properties": {
        "request": {"type": "string"},
        "people": {"type": "array", "items": {"type": "string"}},
        "include": {"type": "array", "items": {"type": "string"}},
        "exclude": {"type": "array", "items": {"type": "string"}},
        "mood": {"type": ["string", "null"]},
        "music": {"type": ["string", "null"]},
        "destination": {"type": ["string", "null"], "enum": ["status", "reel", "story", None]},
    },
}

INTENT_SYSTEM = ("You turn a family member's spoken request (transcript, may be Hindi/Hinglish, may contain ASR "
                 "errors such as व्हील for रील=reel) into a reel-editing intent. " + OUTPUT_RULES)


# ---------------------------------------------------------------- pure helpers

def audio_kind(content_type: str | None, filename: str | None, data: bytes) -> tuple[str, str]:
    """-> (kind, mime). Strips ';codecs=...'; falls back to extension, then magic bytes."""
    ct = (content_type or "").split(";")[0].strip().lower()
    kind = MIME_ALIASES.get(ct)
    if not kind and filename:
        ext = PurePath(filename).suffix.lower().lstrip(".")
        kind = ext if ext in AUDIO_MIME else None
    if not kind:
        kind = sniff_audio(data)
    if not kind:
        raise ExtrasInputError(f"unsupported audio type {ct or filename or 'unknown'}; send m4a/aac/webm/wav/mp3", 415)
    kind = "ogg" if kind == "opus" else kind
    return kind, AUDIO_MIME[kind]


def sniff_audio(b: bytes) -> str | None:
    h = b[:16]
    if h[:4] == b"RIFF" and b[8:12] == b"WAVE":
        return "wav"
    if h[:4] == b"\x1a\x45\xdf\xa3":
        return "webm"
    if h[4:8] == b"ftyp":
        return "m4a"
    if h[:4] == b"OggS":
        return "ogg"
    if h[:4] == b"fLaC":
        return "flac"
    if h[:3] == b"ID3" or (len(h) > 1 and h[0] == 0xFF and (h[1] & 0xE0) == 0xE0):
        # ADTS AAC is 0xFFF1/0xFFF9; MPEG audio otherwise
        return "aac" if (h[1] & 0xF6) == 0xF0 else "mp3"
    if h[:6] == b"#!AMR\n":
        return "amr"
    return None


def build_vocabulary(names: list[str] | None = None, limit: int = 80) -> list[dict]:
    """Dictate vocabulary objects. sounds_like must be unique across entries (else 400)."""
    out: list[dict] = []
    words: set[str] = set()
    sounds: set[str] = set()
    for w, sl, desc in BASE_VOCAB:
        sl = [s for s in sl if s not in sounds and s not in words]
        sounds.update(sl)
        words.add(w)
        e: dict[str, Any] = {"word": w, "description": desc}
        if sl:
            e["sounds_like"] = sl
        out.append(e)
    for n in names or []:
        n = as_str(n, 60)
        if n and n not in words and n not in sounds:
            words.add(n)
            out.append({"word": n, "description": "family member name"})
        if len(out) >= limit:
            break
    return out


def keyterms(names: list[str] | None = None, limit: int = 50) -> list[str]:
    terms = [w for w, _, _ in BASE_VOCAB] + [s for _, sl, _ in BASE_VOCAB for s in sl] + list(names or [])
    return list(dict.fromkeys(t for t in (as_str(x, 60) for x in terms) if t))[:limit]


def _nullish(v: Any) -> str | None:
    s = as_str(v, 120)
    return None if not s or s.lower() in {"null", "none", "n/a", "unknown"} else s


def normalize_intent(raw: Any, transcript: str = "", names: list[str] | None = None) -> dict:
    d = raw if isinstance(raw, dict) else {}
    canon = {**CANON, **{n.lower(): n for n in names or []}}
    people = []
    for p in as_str_list(d.get("people")):
        people.append(canon.get(p, canon.get(p.lower(), p)))
    people = list(dict.fromkeys(people))
    dest = _nullish(d.get("destination"))
    if dest:
        dest = DESTINATIONS.get(dest.lower().strip(), None)
    if not dest:  # infer from words in transcript
        t = transcript.lower()
        for k in ("स्टेटस", "status", "whatsapp", "स्टोरी", "story", "रील", "reel", "instagram"):
            if k in t:
                dest = DESTINATIONS[k]
                break
    mood = _nullish(d.get("mood"))
    return {
        "transcript": transcript,
        "request": as_str(d.get("request"), 400) or transcript,
        "people": people,
        "include": as_str_list(d.get("include")),
        "exclude": as_str_list(d.get("exclude")),
        "mood": mood.lower() if mood else None,
        "music": _nullish(d.get("music")),
        "destination": dest,
    }


# ---------------------------------------------------------------- Sarvam calls

async def _dictate(client: SarvamClient, audio: bytes, mime: str, filename: str, names: list[str],
                   language: str | None) -> dict:
    data = {"vocabulary": json.dumps(build_vocabulary(names), ensure_ascii=False),
            "context": json.dumps({"text": CONTEXT}, ensure_ascii=False), "output_rules": OUTPUT_RULES}
    if language:
        data["language_code"] = language
    r = await client._request("POST", "/v2/dictate", files={"file": (filename, audio, mime)}, data=data,
                              limit_key="stt", kind="dictate", model="dictate", retries=2)
    return r.json()


async def voice_intent(client: SarvamClient, audio: bytes, *, content_type: str | None = None,
                       filename: str | None = None, names: list[str] | None = None,
                       language: str | None = "hi-IN") -> dict:
    """-> {intent, engine_used, timings_ms, corrections, fallback_reason?}"""
    t = Timings()
    if not audio:
        raise ExtrasInputError("empty audio")
    if len(audio) > MAX_AUDIO_BYTES:
        raise ExtrasInputError("audio over 10 MB (max 30 s)", 413)
    if language and language not in STT_LANGS:
        raise ExtrasInputError(f"unsupported language {language!r}")
    names = [n for n in (as_str(x, 60) for x in names or []) if n][:40]
    kind, mime = audio_kind(content_type, filename, audio)
    fname = f"prompt.{kind}"
    reason = None
    transcript = ""
    try:
        with t.span("dictate"):
            j = await _dictate(client, audio, mime, fname, names, language)
        transcript = as_str(j.get("text") or j.get("transcript"), 2000)
        out_txt = (j.get("output") or {}).get("text") or ""
        raw = None
        if out_txt:
            try:
                raw = parse_json_tolerant(out_txt)
            except ValueError:
                raw = None
        if isinstance(raw, dict) and transcript:
            return {"intent": normalize_intent(raw, transcript, names), "engine_used": "dictate",
                    "corrections": j.get("corrections") or [], "timings_ms": t.total()}
        if transcript:  # ASR fine, output_rules failed/degraded -> LLM on the transcript
            reason = f"dictate output unusable (degraded={j.get('degraded')})"
            intent = await _llm_intent(client, transcript, names, t)
            return {"intent": intent, "engine_used": "dictate+sarvam-105b", "fallback_reason": reason,
                    "corrections": j.get("corrections") or [], "timings_ms": t.total()}
        reason = "dictate returned empty transcript"
    except (SarvamQuotaError, SarvamAuthError):
        raise  # account-wide; the fallback would fail the same way
    except SarvamError as e:
        reason = f"dictate failed: {str(e)[:160]}"
        log.warning("%s -> saaras:v4 fallback", reason)
    with t.span("stt_saaras"):
        r = await client.transcribe(audio, mime, fname, language_code=language, keyterms=keyterms(names))
    transcript = as_str(r.get("transcript"), 2000)
    if not transcript:
        raise ExtrasInputError("no speech recognised in the audio", 422)
    intent = await _llm_intent(client, transcript, names, t)
    return {"intent": intent, "engine_used": "saaras:v4+sarvam-105b", "fallback_reason": reason,
            "corrections": [], "timings_ms": t.total()}


async def _llm_intent(client: SarvamClient, transcript: str, names: list[str], t: Timings) -> dict:
    user = (f"Known family names: {', '.join(names) or '(none)'}\nTranscript: {transcript}")
    with t.span("intent_llm"):
        raw = await chat_json(client, INTENT_SYSTEM, user, INTENT_SCHEMA, "voice_intent",
                              reasoning_effort=None, max_tokens=800, temperature=0.1)
    return normalize_intent(raw, transcript, names)
