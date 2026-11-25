"""Reel voiceover + elder confirmation (bulbul:v4-flash streaming TTS) and caption translation (mayura:v1)."""
from __future__ import annotations

import asyncio
import json
import logging
import random
import shutil
import subprocess
import time
import wave
from pathlib import Path

import httpx

from .config import get_settings
from .extras_common import ExtrasInputError, Timings, as_str, cache_get, cache_put, extras_dir, sha
from .sarvam import SarvamAuthError, SarvamClient, SarvamError, SarvamQuotaError
from .timing import record_call

log = logging.getLogger("memories.voiceover")

TTS_MODEL = "bulbul:v4-flash"
TTS_LANGS = {"hi-IN", "en-IN", "bn-IN", "gu-IN", "kn-IN", "ml-IN", "mr-IN", "od-IN", "pa-IN", "ta-IN", "te-IN"}
TRANSLATE_LANGS = TTS_LANGS
DEFAULT_SPEAKER = "simran_hi_narration"
RECOMMENDED_SPEAKERS = ["simran_hi_narration", "roopa_hi_narration", "ratan_hi_latenight_warm"]
MAX_TEXT = 1000
CODECS = {"mp3": "audio/mpeg", "wav": "audio/wav"}

# bulbul:v4-flash persona catalog (Sarvam Voices guide, 2026-11). A speaker outside it is a 400 upstream.
V4_FLASH_SPEAKERS = frozenset("""
aarti_hi_customer aayan_hi_conversational aditi_en_stories aditya_hi_conversational aditya_hi_sales
advait_hi_character amelia_en_conversational amit_hi_conversational anand_hi_documentary anand_hi_news
anand_pa_conversation anand_pa_customer aparna_en_companion aparna_en_edtech aparna_hi_customer aparna_hi_kyc
aravind_ta_ads aravind_ta_suspense arnab_bn_conversation aryaman_hi_ads ashok_hi_character ashok_hi_news
ashutosh_hi_conversational ashwin_en_sports ashwin_en_sports_energetic bhavik_gu_conversation bimal_bn_suspense
chaitra_hi_customer chaitra_kn_conversation chaitra_kn_narration chandrika_en_stories chetan_kn_conversation
chhavi_hi_kids chirag_hi_social dev_en_conversational dev_en_recovery deven_en_conversation girish_en_devotional
girish_en_documentary girish_hi_devotional gokul_ta_narration harpreet_pa_narration ishita_en_customer
ishita_en_medical ishita_en_numbers ishita_en_social ishita_en_stories ishita_hi_ads ishita_hi_ads_informal
ishita_hi_banking ishita_hi_devotional ishita_hi_edtech ishita_hi_numbers ishita_hi_social ishita_mr_conversational
jaspal_pa_banking kabir_hi_conversational kalpit_en_edtech kavitha_te_conversation kavitha_te_narration
kavya_hi_conversational kunal_hi_kids mahesh_hi_documentary manan_hi_conversational mani_hi_conversational
mani_hi_devotional mohit_hi_conversational mrunal_mr_narration mukul_hi_ads mukul_hi_suspense mukul_mr_stories
nachiket_en_ads nachiket_hi_devotional neha_en_customer neha_en_latenight neha_mr_narration nilesh_mr_conversation
nupur_en_kids ojas_en_social payal_en_edtech pooja_gu_conversational pooja_gu_customer pooja_te_conversation
priya_hi_recovery rahul_hi_conversational ratan_hi_customer_expressive ratan_hi_devotional ratan_hi_documentary
ratan_hi_latenight ratan_hi_latenight_warm ratan_hi_recovery ratan_hi_social ratan_hi_sports rehan_hi_social
ritu_en_edtech ritu_en_latenight ritu_en_medical ritu_en_reels ritu_hi_ads_formal ritu_hi_ads_informal
ritu_hi_banking ritu_hi_conversation ritu_hi_customer ritu_hi_customer_utility ritu_hi_customer_warm ritu_hi_edtech
ritu_hi_edtech_bot ritu_hi_insurance ritu_hi_kids ritu_hi_medical ritu_hi_reels ritu_hi_sales ritu_hi_social
ritu_hi_social_lively ritu_mr_insurance ritu_mr_narration rohan_en_recovery roopa_bn_conversational
roopa_en_conversational roopa_hi_companion roopa_hi_conversational roopa_hi_market roopa_hi_narration
roopa_hi_recovery rupali_mr_stories rustom_en_suspense sanchita_en_companion sanchita_en_insurance
sanchita_en_market sanchita_en_recovery sanchita_en_social sanchita_hi_ads_formal sanchita_hi_ads_informal
sanchita_hi_assistant sanchita_hi_banking sanchita_hi_edtech sanchita_hi_feedback sanchita_hi_interview
sanchita_hi_kyc sanchita_hi_market sanchita_hi_romantic sanchita_hi_social sarang_en_narration sarika_hi_conversation
shabana_en_edtech shalini_en_companion shalini_en_customer shalini_hi_companion shalini_hi_social shilpa_hi_narration
shreya_hi_conversational shreya_hi_news shruti_hi_edtech shubh_en_ads shubh_en_audiobook shubh_en_narration
shubh_en_narration_gentle shubh_en_numbers shubh_en_recovery shubh_en_sports shubh_hi_ads shubh_hi_customer
shubh_hi_devotional shubh_hi_ecomm shubh_hi_recovery shubh_hi_stories_dramatic shubh_hi_stories_mixed simran_en_ads
simran_en_automobile simran_en_conversation simran_en_customer simran_en_edtech simran_en_edtech_bot
simran_en_narration simran_en_recovery simran_en_sales simran_en_therapist simran_hi_assistant simran_hi_automobile
simran_hi_conversation simran_hi_latenight simran_hi_narration simran_hi_news simran_hi_news_breaking
simran_hi_recovery simran_hi_sales simran_hi_social_energetic simran_hi_social_excited soham_mr_narration
sophia_en_conversational suchitra_hi_ecomm suchitra_kn_narration suhani_hi_social suman_hi_companion
sumit_hi_conversational sunny_en_social sunny_hi_ads sunny_hi_reels tanya_hi_narration tarun_hi_conversational
tarun_hi_sales tarun_te_narration vaibhav_hi_social vandana_hi_ecomm varun_en_ads varun_en_suspense
vijay_ta_narration vipul_hi_social zarina_en_conversation
""".split())

CONFIRMATIONS = {
    "hi-IN": "आपकी रील तैयार है। देखिए और परिवार के साथ शेयर कीजिए।",
    "en-IN": "Your reel is ready. Watch it and share it with the family.",
}


def validate_speaker(speaker: str | None, language: str) -> str:
    if language not in TTS_LANGS:
        raise ExtrasInputError(f"unsupported language {language!r}; one of {sorted(TTS_LANGS)}")
    sp = (speaker or DEFAULT_SPEAKER).strip()
    if sp not in V4_FLASH_SPEAKERS:
        raise ExtrasInputError(f"speaker {sp!r} is not a {TTS_MODEL} voice; try one of {RECOMMENDED_SPEAKERS}")
    return sp


def audio_duration(path: Path) -> float:
    """Seconds, via ffprobe; WAV header fallback; 0.0 if unknown."""
    if shutil.which("ffprobe"):
        try:
            r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                                "default=nw=1:nk=1", str(path)], capture_output=True, text=True, timeout=10)
            return round(float(r.stdout.strip()), 3)
        except Exception:
            pass
    if path.suffix == ".wav":
        try:
            with wave.open(str(path)) as w:
                return round(w.getnframes() / float(w.getframerate()), 3)
        except Exception:
            pass
    return 0.0


def public_url(path: Path) -> str | None:
    s = get_settings()
    try:
        rel = path.resolve().relative_to(s.data_dir.resolve())
    except ValueError:
        return None
    return f"{s.public_base_url.rstrip('/')}/files/{rel.as_posix()}"


async def _stream_tts(client: SarvamClient, payload: dict, dest: Path, retries: int = 3) -> dict:
    """POST /text-to-speech/stream -> file. Same error semantics as SarvamClient._request
    (402 quota, 401/403 auth, 429/5xx/timeouts retried with exponential backoff + jitter)."""
    if not client.api_key:
        raise SarvamAuthError("SARVAM_API_KEY not set")
    headers = {"api-subscription-key": client.api_key}
    url = client.base_url + "/text-to-speech/stream"
    last: Exception | None = None
    for attempt in range(retries + 1):
        await client.limiter("tts").acquire()
        t0 = time.perf_counter()
        try:
            async with client.http.stream("POST", url, json=payload, headers=headers,
                                          timeout=httpx.Timeout(45, connect=10)) as r:
                if r.status_code >= 400:
                    body = (await r.aread()).decode("utf-8", "replace")[:300]
                    ms = (time.perf_counter() - t0) * 1000
                    record_call("tts_stream", TTS_MODEL, ms, False, status=r.status_code, attempt=attempt)
                    if r.status_code == 402:
                        raise SarvamQuotaError(f"Sarvam credits exhausted (402): {body}")
                    if r.status_code in (401, 403):
                        raise SarvamAuthError(f"Sarvam auth failed ({r.status_code})")
                    if r.status_code == 429 or r.status_code >= 500:
                        ra = r.headers.get("retry-after")
                        delay = float(ra) if ra and ra.replace(".", "").isdigit() else min(20, 1.5 * 2 ** attempt)
                        last = SarvamError(f"{r.status_code}: {body}")
                        log.warning("tts stream -> %s, retry in %.1fs", r.status_code, delay)
                        await asyncio.sleep(delay + random.random())
                        continue
                    raise SarvamError(f"{r.status_code}: {body}")
                ttfb = None
                n = 0
                tmp = dest.with_suffix(dest.suffix + ".part")
                with tmp.open("wb") as f:
                    async for chunk in r.aiter_bytes():
                        if chunk:
                            if ttfb is None:
                                ttfb = (time.perf_counter() - t0) * 1000
                            n += len(chunk)
                            f.write(chunk)
                if n == 0:
                    tmp.unlink(missing_ok=True)
                    raise SarvamError("tts stream returned no audio")
                tmp.replace(dest)
                ms = (time.perf_counter() - t0) * 1000
                record_call("tts_stream", TTS_MODEL, ms, True, ttfb_ms=round(ttfb or ms), attempt=attempt)
                return {"ttfb_ms": round(ttfb or ms), "ms": round(ms), "bytes": n,
                        "content_type": r.headers.get("content-type")}
        except (httpx.TransportError, httpx.TimeoutException) as e:
            record_call("tts_stream", TTS_MODEL, (time.perf_counter() - t0) * 1000, False,
                        error=type(e).__name__, attempt=attempt)
            last = e
            await asyncio.sleep(min(10, 1.0 * 2 ** attempt) + random.random())
    raise SarvamError(f"retries exhausted: {last}")


async def synthesize(client: SarvamClient, text: str, *, language: str = "hi-IN", speaker: str | None = None,
                     codec: str = "mp3", pace: float = 0.95, use_cache: bool = True) -> dict:
    """-> {path, audio_url, duration_s, speaker, language, cached, timings_ms}"""
    t = Timings()
    text = (text or "").strip()
    if not text:
        raise ExtrasInputError("text is empty")
    if len(text) > MAX_TEXT:
        raise ExtrasInputError(f"text over {MAX_TEXT} characters; voiceover lines should be short")
    if codec not in CODECS:
        raise ExtrasInputError(f"codec must be one of {sorted(CODECS)}")
    if not 0.5 <= pace <= 2.0:
        raise ExtrasInputError("pace must be 0.5-2.0")
    sp = validate_speaker(speaker, language)
    key = sha(json.dumps([text, language, sp, codec, pace], ensure_ascii=False))
    path = extras_dir("voiceover") / f"{key}.{codec}"
    meta_hit = cache_get("voiceover", key) if use_cache else None
    if meta_hit and path.exists():
        return {**meta_hit, "path": str(path), "audio_url": public_url(path), "cached": True,
                "timings_ms": t.total()}
    payload = {"text": text, "language_code": language, "model": TTS_MODEL, "speaker": sp, "pace": pace,
               "output_audio_codec": codec}
    with t.span("tts_stream"):
        info = await _stream_tts(client, payload, path)
    t.put("tts_ttfb", info["ttfb_ms"])
    with t.span("probe"):
        dur = audio_duration(path)
    meta = {"duration_s": dur, "speaker": sp, "language": language, "codec": codec, "bytes": info["bytes"],
            "text": text}
    cache_put("voiceover", key, meta)
    return {**meta, "path": str(path), "audio_url": public_url(path), "cached": False, "timings_ms": t.total()}


async def translate(client: SarvamClient, text: str, target: str, source: str = "auto",
                    timings: Timings | None = None) -> str:
    """Caption translation via mayura:v1 (cached)."""
    t = timings or Timings()
    text = (text or "").strip()
    if target not in TRANSLATE_LANGS:
        raise ExtrasInputError(f"unsupported target language {target!r}")
    if not text:
        return ""
    if len(text) > 1000:
        raise ExtrasInputError("text over 1000 characters")
    key = sha(json.dumps([text, target, source], ensure_ascii=False))
    hit = cache_get("translate", key)
    if hit:
        return hit["text"]
    with t.span("translate"):
        out = await client.translate(text, target, source=source)
    out = as_str(out, 4000) or text
    cache_put("translate", key, {"text": out})
    return out


async def confirmation(client: SarvamClient, *, language: str = "hi-IN", speaker: str | None = None,
                       name: str | None = None) -> dict:
    """Spoken 'your reel is ready' for elders. Non-hi/en languages are translated from English first."""
    t = Timings()
    if language not in TTS_LANGS:
        raise ExtrasInputError(f"unsupported language {language!r}")
    text = CONFIRMATIONS.get(language)
    if text is None:
        text = await translate(client, CONFIRMATIONS["en-IN"], language, source="en-IN", timings=t)
    if name:
        text = f"{as_str(name, 40)}, {text}"
    res = await synthesize(client, text, language=language, speaker=speaker)
    res["timings_ms"] = {**t.ms, **res["timings_ms"]}
    return res
