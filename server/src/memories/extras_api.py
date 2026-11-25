"""/v1/extras router: invite card import, voice prompt, voiceover, translate.

Mount with:  from memories.extras_api import router as extras_router; app.include_router(extras_router)
Uses its own lazily created SarvamClient; override with app.dependency_overrides[get_sarvam] = lambda: shared.
Every response (success or error) carries `timings_ms` and `calls` (per Sarvam call latency + status).
"""
from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Awaitable, Callable

import httpx
from fastapi import APIRouter, Depends, File, Form, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from . import db
from .dictate import voice_intent
from .extras_common import ExtrasInputError, Timings
from .invite import process_invite
from .sarvam import SarvamAuthError, SarvamClient, SarvamError, SarvamQuotaError
from .timing import new_trace
from .voiceover import RECOMMENDED_SPEAKERS, TTS_LANGS, confirmation, synthesize, translate

log = logging.getLogger("memories.extras_api")

router = APIRouter(prefix="/v1/extras", tags=["extras"])

_client: SarvamClient | None = None


def get_sarvam() -> SarvamClient:
    global _client
    if _client is None:
        _client = SarvamClient()
    return _client


def _err(status: int, code: str, detail: str, t: Timings, trace: dict, headers: dict | None = None) -> JSONResponse:
    return JSONResponse(status_code=status, headers=headers,
                        content={"error": code, "detail": detail[:400], "timings_ms": t.total(),
                                 "calls": trace["calls"]})


async def _run(fn: Callable[[], Awaitable[dict]], deadline_s: float) -> JSONResponse | dict:
    """Run one extras call with a request trace, an overall deadline and uniform error mapping:
    400/413/415/422 bad input, 402 credits, 429 rate limited after backoff, 502 upstream auth/bad reply,
    504 timeout."""
    trace = new_trace()
    t = Timings()
    try:
        res = await asyncio.wait_for(fn(), timeout=deadline_s)
    except ExtrasInputError as e:
        return _err(e.status, "bad_request", str(e), t, trace)
    except SarvamQuotaError as e:
        return _err(402, "sarvam_quota", str(e), t, trace)
    except SarvamAuthError as e:
        return _err(502, "sarvam_auth", f"upstream rejected the API key: {e}", t, trace)
    except (asyncio.TimeoutError, httpx.TimeoutException):
        return _err(504, "timeout", f"gave up after {deadline_s:.0f} s", t, trace)
    except SarvamError as e:
        msg = str(e)
        if "429" in msg[:40]:
            return _err(429, "sarvam_rate_limited", msg, t, trace, headers={"Retry-After": "10"})
        if "Timeout" in msg or "timed out" in msg:
            return _err(504, "sarvam_timeout", msg, t, trace)
        return _err(502, "sarvam_error", msg, t, trace)
    res.setdefault("timings_ms", t.total())
    res["calls"] = trace["calls"]
    return res


def _names(raw: str | None) -> list[str]:
    if not raw:
        return []
    raw = raw.strip()
    if raw.startswith("["):
        try:
            v = json.loads(raw)
            return [str(x) for x in v if str(x).strip()] if isinstance(v, list) else []
        except ValueError:
            pass
    return [p.strip() for p in raw.split(",") if p.strip()]


@router.post("/invite")
async def invite(image: UploadFile = File(...), album_id: str | None = Form(None), language: str = Form("hi-IN"),
                 refresh: bool = Form(False), sarvam: SarvamClient = Depends(get_sarvam)):
    data = await image.read()

    async def go() -> dict:
        res = await process_invite(sarvam, data, language=language, use_cache=not refresh)
        if album_id:
            db.kv_put("extras_invite", album_id, {"invite": res["invite"], "shot_list": res["shot_list"]})
            res["album_id"] = album_id
        return res

    return await _run(go, 110)


@router.get("/invite/{album_id}")
async def invite_for_album(album_id: str):
    v = db.kv_get("extras_invite", album_id)
    if not v:
        return JSONResponse(status_code=404, content={"error": "not_found", "detail": "no invite for this album"})
    return {**v, "album_id": album_id}


@router.post("/voice-prompt")
async def voice_prompt(audio: UploadFile = File(...), names: str | None = Form(None),
                       language: str | None = Form("hi-IN"), sarvam: SarvamClient = Depends(get_sarvam)):
    data = await audio.read()
    lang = (language or "").strip() or None
    return await _run(lambda: voice_intent(sarvam, data, content_type=audio.content_type, filename=audio.filename,
                                           names=_names(names), language=lang), 60)


class VoiceoverReq(BaseModel):
    text: str = Field(..., min_length=1, max_length=1000)
    language: str = "hi-IN"
    speaker: str | None = None
    codec: str = "mp3"
    pace: float = 0.95


@router.post("/voiceover")
async def voiceover(req: VoiceoverReq, sarvam: SarvamClient = Depends(get_sarvam)):
    return await _run(lambda: synthesize(sarvam, req.text, language=req.language, speaker=req.speaker,
                                         codec=req.codec, pace=req.pace), 60)


class ConfirmReq(BaseModel):
    language: str = "hi-IN"
    speaker: str | None = None
    name: str | None = None


@router.post("/confirmation")
async def confirm(req: ConfirmReq, sarvam: SarvamClient = Depends(get_sarvam)):
    return await _run(lambda: confirmation(sarvam, language=req.language, speaker=req.speaker, name=req.name), 60)


class TranslateReq(BaseModel):
    text: str = Field(..., max_length=1000)
    target: str
    source: str = "auto"


@router.post("/translate")
async def translate_ep(req: TranslateReq, sarvam: SarvamClient = Depends(get_sarvam)):
    async def go() -> dict:
        t = Timings()
        out = await translate(sarvam, req.text, req.target, source=req.source, timings=t)
        return {"text": out, "target": req.target, "timings_ms": t.total()}
    return await _run(go, 30)


@router.get("/voices")
async def voices() -> dict[str, Any]:
    return {"recommended": RECOMMENDED_SPEAKERS, "languages": sorted(TTS_LANGS)}
