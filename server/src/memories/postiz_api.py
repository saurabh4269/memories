"""Post finished reels to social channels through a self-hosted Postiz (Public API).

GET  /v1/post/channels          -> {channels:[{id, provider, name, avatar, disabled}]}
POST /v1/reels/{id}/post        {cut, channel_ids, caption, settings?} -> {posts:[{channel, provider, status, post_id?, url?, error?}]}

Env: POSTIZ_URL (e.g. https://postiz.74-225-200-30.sslip.io), POSTIZ_API_KEY (Settings -> Public API).
Optional: POSTIZ_DISCORD_CHANNEL (default Discord channel id when the request gives none).
Postiz Public API auth is the raw key in `Authorization` (no "Bearer").
"""
from __future__ import annotations

import asyncio
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from . import pipeline

log = logging.getLogger("memories.postiz")
router = APIRouter()

TIMEOUT = httpx.Timeout(30.0, read=300.0, write=300.0)
_transport: httpx.AsyncBaseTransport | None = None  # tests inject httpx.MockTransport


def _cfg() -> tuple[str, str]:
    url = os.getenv("POSTIZ_URL", "").rstrip("/")
    key = os.getenv("POSTIZ_API_KEY", "")
    if not url or not key:
        raise HTTPException(503, "postiz not configured (POSTIZ_URL / POSTIZ_API_KEY)")
    return url + "/api/public/v1", key


def _client() -> httpx.AsyncClient:
    base, key = _cfg()
    return httpx.AsyncClient(base_url=base, headers={"Authorization": key}, timeout=TIMEOUT,
                             transport=_transport)


def _err(r: httpx.Response) -> str:
    try:
        j = r.json()
        msg = j.get("message") or j.get("error") or j
    except Exception:
        msg = r.text
    return f"postiz {r.status_code}: {str(msg)[:300]}"


async def _integrations(c: httpx.AsyncClient) -> list[dict]:
    r = await c.get("/integrations")
    if r.status_code >= 400:
        raise HTTPException(502 if r.status_code != 401 else 503, _err(r))
    data = r.json()
    return data if isinstance(data, list) else (data.get("integrations") or [])


def _provider(i: dict) -> str:
    return i.get("identifier") or i.get("providerIdentifier") or i.get("provider") or ""


def public_channel(i: dict) -> dict:
    return {"id": i.get("id"), "provider": _provider(i), "name": i.get("name") or i.get("display") or "",
            "avatar": i.get("picture") or i.get("avatar"), "disabled": bool(i.get("disabled"))}


def default_settings(provider: str, caption: str) -> dict[str, Any]:
    """Minimal per-provider `settings` Postiz validates for a video post."""
    s: dict[str, Any] = {"__type": provider}
    title = (caption or "Memories").strip().splitlines()[0][:90] or "Memories"
    if provider == "discord":
        if os.getenv("POSTIZ_DISCORD_CHANNEL"):
            s["channel"] = os.getenv("POSTIZ_DISCORD_CHANNEL")
    elif provider == "youtube":
        s.update(title=title, type="public")
    elif provider in ("instagram", "instagram-standalone"):
        s.update(post_type="post")
    elif provider == "tiktok":
        s.update(privacy_level="PUBLIC_TO_EVERYONE", duet=False, stitch=False, comment=True,
                 autoAddMusic="no", brand_content_toggle=False, brand_organic_toggle=False,
                 content_posting_method="DIRECT_POST")
    elif provider == "reddit":
        s["subreddit"] = []
    elif provider == "pinterest":
        s.update(title=title)
    return s


@router.get("/v1/post/channels")
async def channels():
    async with _client() as c:
        items = await _integrations(c)
    return {"channels": [public_channel(i) for i in items]}


class PostRequest(BaseModel):
    cut: int = 0
    channel_ids: list[str] = Field(default_factory=list)
    caption: str = ""
    # optional per-channel overrides merged into Postiz `settings`, e.g. {"<discord id>": {"channel": "123"}}
    settings: dict[str, dict[str, Any]] = Field(default_factory=dict)


async def _final_file(reel: dict, idx: int) -> tuple[bytes, str]:
    """Return the cut's final mp4 bytes (render it if needed; fall back to downloading final_url)."""
    cut = reel["cuts"][idx]
    final = cut.get("final") or {}
    if cut.get("final_status") != "done" or not final:
        from . import api  # lazy: shared ImmichClient lives in api.state
        final = await pipeline.render_final(api.state["immich"], reel, idx)
        if cut.get("final_status") != "done" or not final:
            raise HTTPException(409, f"final render not ready: {cut.get('final_error') or cut.get('final_status')}")
    p = Path(final.get("path") or "")
    if p.is_file():
        return await asyncio.to_thread(p.read_bytes), p.name
    url = final.get("url")
    if not url:
        raise HTTPException(409, "final mp4 missing")
    async with httpx.AsyncClient(timeout=TIMEOUT, follow_redirects=True, transport=_transport) as h:
        r = await h.get(url)
        if r.status_code >= 400:
            raise HTTPException(502, f"could not fetch final mp4 ({r.status_code})")
        return r.content, url.rsplit("/", 1)[-1] or "reel.mp4"


async def _upload(c: httpx.AsyncClient, data: bytes, name: str) -> dict:
    r = await c.post("/upload", files={"file": (name, data, "video/mp4")})
    if r.status_code >= 400:
        raise HTTPException(502, "upload failed: " + _err(r))
    m = r.json()
    if not m.get("id") or not m.get("path"):
        raise HTTPException(502, f"upload returned no media id/path: {str(m)[:200]}")
    return m


async def _post_one(c: httpx.AsyncClient, integ: dict, media: dict, caption: str, extra: dict) -> dict:
    prov = _provider(integ)
    out = {"channel": integ["id"], "provider": prov, "name": integ.get("name")}
    settings = {**default_settings(prov, caption), **(extra or {})}
    if prov == "discord" and not settings.get("channel"):
        return {**out, "status": "error", "error": "discord needs settings.channel (pass settings or POSTIZ_DISCORD_CHANNEL)"}
    body = {
        "type": "now",
        "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "shortLink": False,
        "tags": [],
        "posts": [{
            "integration": {"id": integ["id"]},
            "value": [{"content": caption, "image": [{"id": media["id"], "path": media["path"]}]}],
            "settings": settings,
        }],
    }
    try:
        r = await c.post("/posts", json=body)
    except httpx.HTTPError as e:
        return {**out, "status": "error", "error": f"postiz unreachable: {e}"[:300]}
    if r.status_code >= 400:
        return {**out, "status": "error", "error": _err(r)}
    res = r.json()
    first = (res[0] if isinstance(res, list) and res else res) or {}
    post_id = first.get("postId") or first.get("id")
    return {**out, "status": "queued", "post_id": post_id, "group": first.get("group"),
            "url": first.get("releaseURL") or first.get("url")}


@router.post("/v1/reels/{reel_id}/post")
async def post_reel(reel_id: str, body: PostRequest):
    reel = pipeline.load(reel_id)
    if not reel:
        raise HTTPException(404, "reel not found")
    if not 0 <= body.cut < len(reel.get("cuts", [])):
        raise HTTPException(400, "bad cut index")
    if not body.channel_ids:
        raise HTTPException(400, "channel_ids required")
    _cfg()
    caption = body.caption or reel["cuts"][body.cut].get("title") or ""
    async with _client() as c:
        by_id = {i["id"]: i for i in await _integrations(c)}
        unknown = [cid for cid in body.channel_ids if cid not in by_id]
        known = [by_id[cid] for cid in body.channel_ids if cid in by_id]
        posts = [{"channel": cid, "status": "error", "error": "unknown channel"} for cid in unknown]
        if known:
            data, name = await _final_file(reel, body.cut)
            media = await _upload(c, data, name)
            posts += await asyncio.gather(*[_post_one(c, i, media, caption, body.settings.get(i["id"], {}))
                                            for i in known])
    log.info("postiz post reel=%s cut=%s -> %s", reel_id, body.cut, [(p["channel"], p["status"]) for p in posts])
    return {"reel_id": reel_id, "cut": body.cut, "posts": posts}
