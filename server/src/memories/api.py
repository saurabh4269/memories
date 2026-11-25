"""FastAPI app: reels, finals, analysis, coach, invite, shared-tracking, static outputs."""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import coach, flags, pipeline
from .analysis import analyse_album, poller
from .captions import HAS_RAQM
from .config import get_settings
from .db import watch_album
from .immich import ImmichClient
from .sarvam import SarvamAuthError, SarvamClient, SarvamQuotaError
from .timing import new_trace

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("memories.api")

state: dict[str, Any] = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    s = get_settings()
    state["immich"] = ImmichClient()
    state["sarvam"] = SarvamClient()
    stop = asyncio.Event()
    task = None
    if s.poll_interval_s > 0 and state["immich"].configured:
        task = asyncio.create_task(poller(state["immich"], state["sarvam"], s.poll_interval_s, stop))
    yield
    stop.set()
    if task:
        task.cancel()
    flags.close()
    await state["immich"].aclose()
    await state["sarvam"].aclose()


app = FastAPI(title="Memories director", version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
get_settings().data_dir.mkdir(parents=True, exist_ok=True)
app.mount("/files", StaticFiles(directory=str(get_settings().data_dir)), name="files")


def _mode() -> str:
    return flags.mode(flags._cache[1]) if flags._cache else "normal"


@app.exception_handler(SarvamQuotaError)
async def _quota(_, exc):
    from fastapi.responses import JSONResponse
    return JSONResponse(status_code=402, content={"error": "sarvam_quota", "detail": str(exc)[:200], "mode": _mode()})


@app.exception_handler(SarvamAuthError)
async def _auth(_, exc):
    from fastapi.responses import JSONResponse
    return JSONResponse(status_code=502, content={"error": "sarvam_auth", "detail": str(exc)[:200], "mode": _mode()})


@app.get("/studio", include_in_schema=False)
async def studio():
    from fastapi.responses import HTMLResponse
    from pathlib import Path
    return HTMLResponse((Path(__file__).parent / "static/studio.html").read_text())


@app.get("/v1/albums")
async def albums():
    al = await state["immich"].list_albums()
    al = sorted(al, key=lambda a: a.get("updatedAt") or "", reverse=True)
    return {"albums": [{"id": a["id"], "albumName": a.get("albumName"), "assetCount": a.get("assetCount", 0)} for a in al],
            "mode": _mode()}


@app.get("/health")
async def health():
    s = get_settings()
    return {"ok": True, "immich_configured": state["immich"].configured, "sarvam_configured": bool(s.sarvam_api_key),
            "flagsmith_configured": bool(s.flagsmith_server_key), "raqm": HAS_RAQM, "mode": _mode()}


@app.get("/v1/flags")
async def get_flags(member: str | None = None):
    f = flags.identity_flags(member) if member else flags.env_flags()
    return {"flags": f, "mode": flags.mode(f)}


@app.get("/v1/members/flags")
async def member_flags(member: str, language: str | None = None, role: str | None = None):
    traits = {k: v for k, v in (("language", language), ("role", role)) if v}
    f = await asyncio.to_thread(flags.identity_flags, member, traits or None)
    return {"member": member, "traits": traits, "flags": f, "mode": flags.mode(f)}


class ReelRequest(BaseModel):
    album_id: str
    prompt: str | None = None
    destination: str = "wa_status"
    member_name: str | None = None
    language: str | None = None


@app.post("/v1/reels")
async def create_reel(request: Request):
    ct = request.headers.get("content-type", "")
    audio = None
    if ct.startswith("multipart/"):
        form = await request.form()
        body = ReelRequest(**{k: v for k, v in form.items() if k in ReelRequest.model_fields and isinstance(v, str)})
        up = form.get("audio")
        if up is not None and hasattr(up, "read"):
            audio = (await up.read(), up.content_type or "audio/wav", up.filename or "audio.wav")
    else:
        body = ReelRequest(**(await request.json()))
    if not body.prompt and not audio:
        body.prompt = ""
    reel = await pipeline.create_reel(state["immich"], state["sarvam"], album_id=body.album_id, prompt=body.prompt,
                                      destination=body.destination, member_name=body.member_name,
                                      language=body.language, audio=audio)
    return pipeline.public_reel(reel)


@app.get("/v1/reels/{reel_id}")
async def get_reel(reel_id: str):
    reel = pipeline.load(reel_id)
    if not reel:
        raise HTTPException(404, "reel not found")
    out = pipeline.public_reel(reel)
    out["mode"] = _mode()
    return out


@app.post("/v1/reels/{reel_id}/final/{cut}")
async def final(reel_id: str, cut: int):
    reel = pipeline.load(reel_id)
    if not reel:
        raise HTTPException(404, "reel not found")
    if not 0 <= cut < len(reel.get("cuts", [])):
        raise HTTPException(400, "bad cut index")
    new_trace()
    res = await pipeline.render_final(state["immich"], reel, cut)
    c = reel["cuts"][cut]
    return {"reel_id": reel_id, "cut": cut, "status": c.get("final_status"), "final_url": res.get("url"),
            "cover_url": res.get("cover_url"), "timings": res.get("timings"), "error": c.get("final_error"),
            "mode": _mode()}


class SharedRequest(BaseModel):
    member_name: str | None = None
    cut: int | None = None
    target: str | None = None


@app.post("/v1/reels/{reel_id}/shared")
async def shared(reel_id: str, body: SharedRequest | None = None):
    reel = pipeline.load(reel_id) or {}
    member = (body.member_name if body else None) or reel.get("member_name") or "anonymous"
    ok = await asyncio.to_thread(flags.track, "reel_shared", member, reel_id=reel_id,
                                 strategy=reel.get("strategy"), cut=body.cut if body else None,
                                 target=body.target if body else None)
    return {"tracked": ok, "mode": _mode()}


@app.post("/v1/albums/{album_id}/analyse")
async def analyse(album_id: str, limit: int | None = None):
    new_trace()
    watch_album(album_id)
    lite = flags.ml_lite(await asyncio.to_thread(flags.env_flags))
    res = await analyse_album(state["immich"], state["sarvam"], album_id, batch=(lite or {}).get("analysis_batch"),
                              limit=limit)
    return {"album_id": album_id, "stats": res["stats"], "mode": _mode()}


@app.get("/v1/albums/{album_id}/coach")
async def get_coach(album_id: str, member: str | None = None, lang: str | None = None, cohort: str | None = None,
                    language: str | None = None, role: str | None = None):
    traits = {k: v for k, v in (("cohort", cohort), ("language", language), ("role", role)) if v}
    return await coach.coach_cards(state["sarvam"], state["immich"], album_id, member, lang, traits)


@app.post("/v1/events/{album_id}/invite")
async def invite(album_id: str, request: Request):
    form = await request.form()
    up = form.get("file") or form.get("image")
    if up is None or not hasattr(up, "read"):
        raise HTTPException(400, "multipart field 'file' required")
    res = await coach.extract_invite(state["sarvam"], album_id, await up.read(), up.content_type or "image/jpeg",
                                     up.filename or "invite.jpg")
    return {"album_id": album_id, "event_context": res, "mode": _mode()}


try:  # Sarvam extras (invite / voice prompt / voiceover) built separately
    from memories import extras_api
    app.include_router(extras_api.router)
    if hasattr(extras_api, "get_sarvam"):
        app.dependency_overrides[extras_api.get_sarvam] = lambda: state["sarvam"]
except ImportError:
    pass


# Optional routers owned by other modules (docs/API-CONTRACT.md): load when present, skip otherwise.
for _mod in ("memories.editor_api", "memories.join_api", "memories.postiz_api", "memories.facet_api"):
    try:
        import importlib

        app.include_router(importlib.import_module(_mod).router)
        log.info("router loaded: %s", _mod)
    except ImportError as e:
        log.info("router %s not available (%s), skipping", _mod, e)
    except Exception as e:  # a broken optional module must not take the director down
        log.warning("router %s failed to load: %s", _mod, e)
