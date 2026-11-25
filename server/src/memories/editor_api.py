"""Editor endpoints: EDL for the app's live preview, Immich media proxy, clip edits + re-render, alternatives, OTIO.

Included by api.py (`router`). Reuses pipeline.build_specs + render.render_reel (segment cache) for re-renders.
"""
from __future__ import annotations

import asyncio
import io
import logging
import time
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse, Response, StreamingResponse
from pydantic import BaseModel
from starlette.background import BackgroundTask

from . import db, pipeline
from .config import get_settings
from .immich import ImmichClient

log = logging.getLogger("memories.editor_api")

router = APIRouter(tags=["editor"])

# keep in sync with render.XFADE / director limits (imported lazily to avoid touching modules under edit)
PHOTO_MIN, PHOTO_MAX, PHOTO_DEFAULT = 1.2, 4.5, 2.4
VIDEO_MIN, VIDEO_MAX = 1.2, 6.0
MAX_CLIPS = 20

_immich: ImmichClient | None = None
_bg: set[asyncio.Task] = set()


def immich() -> ImmichClient:
    global _immich
    try:  # share the app's client when running inside api.py
        from memories.api import state
        if state.get("immich"):
            return state["immich"]
    except Exception:
        pass
    if _immich is None:
        _immich = ImmichClient()
    return _immich


def base_url() -> str:
    return get_settings().public_base_url.rstrip("/")


def xfade_s() -> float:
    from .render import XFADE
    return XFADE


# ---------------------------------------------------------------- pure helpers (unit tested)

def clip_base_len(c: dict) -> float:
    return float(c["out_s"]) - float(c["in_s"]) if c.get("kind") == "video" else float(c["hold_s"])


def clip_timing(clips: list[dict], transitions: str = "cut", xfade: float = 0.35) -> tuple[list[tuple[float, float]], float]:
    """(start_s, duration_s) per clip exactly like the renderer: segment duration = base (+ xfade overlap for all
    but the last clip when transitions != cut); clip k starts at sum(d_j - overlap_j for j<k)."""
    n = len(clips)
    out: list[tuple[float, float]] = []
    t = 0.0
    for i, c in enumerate(clips):
        overlap = xfade if (transitions != "cut" and i < n - 1) else 0.0
        dur = round(clip_base_len(c) + overlap, 3)
        out.append((round(t, 3), dur))
        t += dur - overlap
    return out, round(t, 3)


def media_urls(asset_id: str, kind: str, base: str) -> tuple[str, str]:
    poster = f"{base}/v1/assets/{asset_id}/image?size=thumbnail"
    if kind == "video":
        return f"{base}/v1/assets/{asset_id}/video", poster
    return f"{base}/v1/assets/{asset_id}/image?size=preview", poster


def photo_focus(asset_id: str, analysis: dict | None, faces: list | None) -> list[float]:
    sc = (analysis or {}).get("subject_center") or [0.5, 0.5]
    focus = [float(sc[0]), float(sc[1])]
    if faces:
        xs, ys = [], []
        for f in faces:
            iw, ih = f.get("imageWidth") or 1, f.get("imageHeight") or 1
            xs += [f["boundingBoxX1"] / iw, f["boundingBoxX2"] / iw]
            ys += [f["boundingBoxY1"] / ih, f["boundingBoxY2"] / ih]
        focus = [(min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2]
    return [round(focus[0], 3), round(focus[1], 3)]


def build_edl(cut: dict, idx: int, base: str, transitions: str = "cut", xfade: float = 0.35,
              analysis: dict[str, dict] | None = None, faces: dict[str, list] | None = None,
              durations: dict[str, float] | None = None) -> dict:
    analysis, faces, durations = analysis or {}, faces or {}, durations or {}
    clips = cut.get("clips") or []
    timing, total = clip_timing(clips, transitions, xfade)
    out_clips, captions = [], []
    for i, (c, (start, dur)) in enumerate(zip(clips, timing)):
        kind = c.get("kind", "photo")
        aid = c["asset_id"]
        media, poster = media_urls(aid, kind, base)
        focus = photo_focus(aid, analysis.get(aid), faces.get(aid) if kind == "photo" else None)
        if kind == "photo":
            zoom_in = i % 2 == 0  # same alternation as pipeline.build_specs
            kb = {"from": 1.0 if zoom_in else 1.08, "to": 1.08 if zoom_in else 1.0, "focus": focus}
        else:
            kb = {"from": 1.0, "to": 1.0, "focus": focus}
        visible = round(clip_base_len(c), 3)
        item = {"asset_id": aid, "type": kind, "media_url": media, "poster_url": poster,
                "in_s": float(c.get("in_s") or 0.0), "out_s": float(c.get("out_s") or 0.0),
                "hold_s": float(c.get("hold_s") or 0.0), "start_s": start, "duration_s": dur,
                "visible_s": visible, "caption": c.get("caption") or "", "kenburns": kb}
        if durations.get(aid):
            item["source_duration_s"] = durations[aid]
        out_clips.append(item)
        if c.get("caption"):
            captions.append({"text": c["caption"], "start_s": start, "duration_s": visible, "clip_index": i,
                             "asset_id": aid})
    m = cut.get("music") or {}
    music = {"url": f"{base}/v1/music/{m['file']}" if m.get("file") else None, "bpm": m.get("bpm"),
             "start_s": float(m.get("beat_offset") or 0.0), "title": m.get("title"),
             "attribution": m.get("attribution")}
    return {"cut": idx, "version": cut.get("version", 0), "title": cut.get("title"), "duration_s": total,
            "music": music, "clips": out_clips, "captions": captions,
            "transitions": {"type": transitions, "duration_s": xfade if transitions != "cut" else 0.0},
            "cover_asset_id": cut.get("cover_asset_id"),
            "preview_url": (cut.get("preview") or {}).get("url"), "final_url": (cut.get("final") or {}).get("url"),
            "final_status": cut.get("final_status", "pending")}


def validate_clips(req: list[dict], old: list[dict], rows_by_id: dict[str, dict]) -> tuple[list[dict], list[str]]:
    """Edited clip list -> renderer clips. Raises ValueError on bad input; clamps times/lengths."""
    if not req:
        raise ValueError("clips must not be empty")
    if len(req) > MAX_CLIPS:
        raise ValueError(f"at most {MAX_CLIPS} clips")
    ids = [c.get("asset_id") for c in req]
    dups = sorted({i for i in ids if ids.count(i) > 1})
    if dups:
        raise ValueError(f"duplicate asset_id(s): {', '.join(map(str, dups))}")
    prev = {c["asset_id"]: c for c in old}
    notes: list[str] = []
    out = []
    for c in req:
        aid = c["asset_id"]
        row = rows_by_id.get(aid)
        if row is None:
            raise ValueError(f"asset {aid} is not in this album")
        p = prev.get(aid, {})
        cap = c.get("caption") if c.get("caption") is not None else p.get("caption", "")
        cap = str(cap or "")[:80]
        if row.get("type") == "VIDEO":
            dur = float(row.get("duration") or 0.0)
            an = row.get("analysis") or {}
            bw = an.get("best_window") or [0.0, 0.0]
            d_in = p.get("in_s", bw[0] if bw[1] > bw[0] else 0.0)
            d_out = p.get("out_s", bw[1] if bw[1] > bw[0] else d_in + 3.0)
            in_s = float(c["in_s"]) if c.get("in_s") is not None else float(d_in)
            out_s = float(c["out_s"]) if c.get("out_s") is not None else float(d_out)
            hi = dur if dur > 0 else max(out_s, in_s + VIDEO_MIN)
            in_s0, out_s0 = in_s, out_s
            in_s = min(max(0.0, in_s), max(0.0, hi - VIDEO_MIN))
            out_s = min(max(out_s, in_s + min(VIDEO_MIN, hi - in_s)), in_s + VIDEO_MAX, hi)
            if (round(in_s, 3), round(out_s, 3)) != (round(in_s0, 3), round(out_s0, 3)):
                notes.append(f"{aid[:8]}: clamped {in_s0:.2f}-{out_s0:.2f} to {in_s:.2f}-{out_s:.2f}")
            out.append({"asset_id": aid, "kind": "video", "in_s": round(in_s, 3), "out_s": round(out_s, 3),
                        "hold_s": 0.0, "caption": cap, "max_len": round(hi - in_s, 3)})
        else:
            hold0 = float(c["hold_s"]) if c.get("hold_s") is not None else float(p.get("hold_s") or PHOTO_DEFAULT)
            hold = min(max(hold0, PHOTO_MIN), PHOTO_MAX)
            if round(hold, 3) != round(hold0, 3):
                notes.append(f"{aid[:8]}: hold clamped {hold0:.2f} to {hold:.2f}")
            out.append({"asset_id": aid, "kind": "photo", "in_s": 0.0, "out_s": 0.0, "hold_s": round(hold, 3),
                        "caption": cap, "max_len": PHOTO_MAX})
    return out, notes


def _hamming(a: int, b: int) -> int:
    return bin(int(a) ^ int(b)).count("1")


def rank_alternatives(rows: list[dict], cut_clips: list[dict], slot: int, top: int = 6) -> list[dict]:
    """Rank album rows not in the cut: quality / people / team score + similarity to the slot's clip."""
    used = {c["asset_id"] for c in cut_clips}
    by_id = {r["id"]: r for r in rows}
    ref = by_id.get(cut_clips[slot]["asset_id"]) if 0 <= slot < len(cut_clips) else None
    ref_an = (ref or {}).get("analysis") or {}
    ref_people = set((ref or {}).get("person_ids") or [])
    ref_t = _ts((ref or {}).get("time"))
    scored = []
    for r in rows:
        if r["id"] in used:
            continue
        an = r.get("analysis") or {}
        if an.get("dup_of"):
            continue
        q = float(an.get("quality") or 5)
        people_n = int(an.get("people_count") or len(r.get("people") or []) or 0)
        team_s = float(r.get("team_score") or 0.0)
        s = q + 0.4 * max(0.0, team_s) + 0.4 * min(people_n, 4)
        reasons: list[tuple[float, str]] = [(q / 3, f"quality {q:.0f}/10")]
        if team_s >= 3:
            reasons.append((team_s / 2, "your team is in it"))
        if ref is not None:
            if r.get("type") == ref.get("type"):
                s += 1.0
                reasons.append((0.5, "same kind of shot (" + ("video" if r.get("type") == "VIDEO" else "photo") + ")"))
            shared = len(ref_people & set(r.get("person_ids") or []))
            if shared:
                s += 1.2 * min(shared, 3)
                names = [n for n in (r.get("people") or []) if n in set((ref or {}).get("people") or [])]
                reasons.append((1.5 * shared + 1.5, "same people" + (f" ({', '.join(names[:2])})" if names else "")))
            t = _ts(r.get("time"))
            if ref_t and t:
                gap_min = abs(t - ref_t) / 60
                if gap_min <= 15:
                    s += 2.0 * (1 - gap_min / 15)
                    reasons.append((2.2 * (1 - gap_min / 15) + 0.5, "taken within a minute of the current clip" if gap_min < 1 else f"taken {gap_min:.0f} min from the current clip"))
            for k, label in (("activity", "same activity"), ("moment_tag", "same moment"), ("mood", "same mood")):
                if an.get(k) and an.get(k) == ref_an.get(k):
                    s += 1.0 if k != "mood" else 0.5
                    reasons.append((1.0, f"{label}: {str(an[k]).replace('_', ' ')}"))
                    break
            if r.get("phash") is not None and ref.get("phash") is not None:
                hd = _hamming(r["phash"], ref["phash"])
                if hd <= 18:
                    s += (18 - hd) / 9
                    reasons.append(((18 - hd) / 6, "looks similar"))
        reasons.sort(key=lambda x: -x[0])
        cap = (an.get("caption") or "").strip()
        why = "; ".join(x[1] for x in reasons[:2])
        if cap:
            why = f"{cap[:70]} - {why}"
        scored.append((round(s, 2), r, why))
    scored.sort(key=lambda x: -x[0])
    return [{"asset_id": r["id"], "type": "video" if r.get("type") == "VIDEO" else "photo", "score": s, "why": why,
             "duration_s": r.get("duration") or None} for s, r, why in scored[:top]]


def _ts(t: str | None) -> float | None:
    if not t:
        return None
    from datetime import datetime
    try:
        return datetime.fromisoformat(str(t).replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


# ---------------------------------------------------------------- loaders

def _reel_cut(reel_id: str, cut: int) -> tuple[dict, dict]:
    reel = pipeline.load(reel_id)
    if not reel:
        raise HTTPException(404, "reel not found")
    cuts = reel.get("cuts") or []
    if not 0 <= cut < len(cuts):
        raise HTTPException(400, f"bad cut index (0..{len(cuts) - 1})")
    return reel, cuts[cut]


def _transitions(reel: dict, profile: str = "preview") -> str:
    from .render import profile_from
    return profile_from(profile, reel.get("render_overrides")).transitions


def edl_for(reel: dict, idx: int, durations: dict[str, float] | None = None) -> dict:
    cut = reel["cuts"][idx]
    ids = [c["asset_id"] for c in cut.get("clips") or []]
    analysis = db.get_analysis(ids)
    faces = {i: f for i in ids if (f := db.kv_get("faces", i))}
    edl = build_edl(cut, idx, base_url(), _transitions(reel), xfade_s(), analysis, faces, durations)
    edl["reel_id"] = reel["reel_id"]
    return edl


# ---------------------------------------------------------------- routes: EDL / OTIO

@router.get("/v1/reels/{reel_id}/cuts/{cut}/edl")
async def get_edl(reel_id: str, cut: int):
    reel, _ = _reel_cut(reel_id, cut)
    return edl_for(reel, cut)


@router.get("/v1/reels/{reel_id}/cuts/{cut}/otio")
async def get_otio(reel_id: str, cut: int):
    from .analysis import load_rows
    from .otio_export import to_otio_json
    reel, _ = _reel_cut(reel_id, cut)
    durations: dict[str, float] = {}
    try:
        durations = {r["id"]: r["duration"] for r in await load_rows(immich(), reel["album_id"]) if r.get("duration")}
    except Exception as e:
        log.warning("otio: album rows unavailable (%s); exporting without source durations", e)
    edl = edl_for(reel, cut, durations)
    body = await asyncio.to_thread(to_otio_json, edl, f"Memories {reel_id} cut {cut}: {edl.get('title') or ''}")
    fn = f"memories-{reel_id}-{cut}.otio"
    return Response(body, media_type="application/json",
                    headers={"Content-Disposition": f'attachment; filename="{fn}"'})


# ---------------------------------------------------------------- routes: media proxy

def _proxy_dir(size: str) -> Path:
    d = get_settings().data_dir / "cache" / "proxy" / size
    d.mkdir(parents=True, exist_ok=True)
    return d


def _to_jpeg(b: bytes) -> bytes:
    if b[:3] == b"\xff\xd8\xff":
        return b
    from PIL import Image
    im = Image.open(io.BytesIO(b)).convert("RGB")
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=85)
    return buf.getvalue()


_CACHE_HDR = {"Cache-Control": "public, max-age=86400"}


@router.get("/v1/assets/{asset_id}/image")
async def asset_image(asset_id: str, size: str = "preview"):
    if size not in ("preview", "thumbnail"):
        raise HTTPException(400, "size must be preview or thumbnail")
    p = _proxy_dir(size) / f"{asset_id}.jpg"
    if not p.exists():
        shared = get_settings().data_dir / "cache" / "preview" / f"{asset_id}.jpg"  # pipeline's render cache
        if size == "preview" and shared.exists():
            data = shared.read_bytes()
        else:
            try:
                data = await immich().preview(asset_id, size)
            except Exception as e:
                code = getattr(getattr(e, "response", None), "status_code", 502)
                raise HTTPException(404 if code in (400, 404) else 502, f"immich thumbnail failed: {code}")
        data = await asyncio.to_thread(_to_jpeg, data)
        tmp = p.with_suffix(f".{time.time_ns()}.tmp")
        tmp.write_bytes(data)
        tmp.replace(p)
    return FileResponse(p, media_type="image/jpeg", headers=_CACHE_HDR)


_PASS = ("content-type", "content-length", "content-range", "accept-ranges", "etag", "last-modified")


@router.api_route("/v1/assets/{asset_id}/video", methods=["GET", "HEAD"])
async def asset_video(asset_id: str, request: Request):
    im = immich()
    hdr = {"x-api-key": im.api_key}
    for h in ("range", "if-range", "if-none-match"):
        if request.headers.get(h):
            hdr[h] = request.headers[h]
    req = im.http.build_request(request.method, im.playback_url(asset_id), headers=hdr,
                                timeout=None if request.method == "GET" else 30)
    r = await im.http.send(req, stream=True)
    if r.status_code >= 400 and r.status_code != 416:
        await r.aclose()
        raise HTTPException(404 if r.status_code in (400, 404) else 502, f"immich playback failed: {r.status_code}")
    out = {k: r.headers[k] for k in _PASS if k in r.headers}
    out.setdefault("accept-ranges", "bytes")
    out["cache-control"] = "public, max-age=3600"
    if request.method == "HEAD":
        await r.aclose()
        return Response(status_code=r.status_code, headers=out)
    return StreamingResponse(r.aiter_raw(), status_code=r.status_code, headers=out,
                             background=BackgroundTask(r.aclose))


@router.get("/v1/music/{file}")
async def music_file(file: str):
    d = (get_settings().assets_dir / "music").resolve()
    p = (d / file).resolve()
    if p.parent != d or not p.is_file():
        raise HTTPException(404, "no such track")
    return FileResponse(p, media_type="audio/mpeg", headers=_CACHE_HDR)


# ---------------------------------------------------------------- routes: alternatives

@router.get("/v1/reels/{reel_id}/cuts/{cut}/alternatives")
async def alternatives(reel_id: str, cut: int, slot: int = 0, n: int = 6):
    from .analysis import load_rows
    reel, c = _reel_cut(reel_id, cut)
    clips = c.get("clips") or []
    if not 0 <= slot < len(clips):
        raise HTTPException(400, f"bad slot (0..{len(clips) - 1})")
    rows = await load_rows(immich(), reel["album_id"])
    for r in rows:
        if not r.get("analysis") and r.get("stale_analysis"):
            r["analysis"] = r["stale_analysis"]
        if r["type"] == "IMAGE":
            h = db.kv_get("phash", r["id"])
            if h is not None:
                r["phash"] = h
    try:
        from .team import score_rows
        score_rows(rows)
    except Exception as e:
        log.debug("team scoring unavailable: %s", e)
    alts = rank_alternatives(rows, clips, slot, top=max(1, min(n, 20)))
    base = base_url()
    for a in alts:
        media, poster = media_urls(a["asset_id"], a["type"], base)
        a["poster_url"], a["media_url"] = poster, media
    return {"reel_id": reel_id, "cut": cut, "slot": slot, "slot_asset_id": clips[slot]["asset_id"],
            "alternatives": alts}


# ---------------------------------------------------------------- routes: edit + re-render

class EditClip(BaseModel):
    asset_id: str
    in_s: float | None = None
    out_s: float | None = None
    hold_s: float | None = None
    caption: str | None = None


class EditRequest(BaseModel):
    cut: int
    clips: list[EditClip]
    music_mood: str | None = None
    title: str | None = None


async def _render_version(reel: dict, idx: int, profile_name: str, rows_by_id: dict) -> dict:
    """Like pipeline.render_cut but writes a versioned file (cut{idx}_v{n}_{profile}.mp4); segment cache reused."""
    from .render import profile_from, render_reel
    cut = reel["cuts"][idx]
    p = profile_from(profile_name, reel.get("render_overrides"))
    t0 = time.perf_counter()
    specs = await pipeline.build_specs(immich(), cut, rows_by_id, p.transitions)
    prep_ms = round((time.perf_counter() - t0) * 1000)
    out = pipeline.reels_dir() / reel["reel_id"] / f"cut{idx}_v{cut.get('version', 0)}_{profile_name}.mp4"
    music = cut.get("music") or {}
    ci = next((i for i, c in enumerate(cut["clips"]) if c["asset_id"] == cut.get("cover_asset_id")), 0)
    timings = await asyncio.to_thread(render_reel, specs, out, p, music.get("path"),
                                      float(music.get("beat_offset") or 0.0), None, ci)
    timings["prep_ms"] = prep_ms
    timings.pop("captions", None)
    timings["profile"] = {"name": p.name, "w": p.w, "h": p.h, "fps": p.fps}
    return {"url": pipeline.public_url(out), "cover_url": pipeline.public_url(out.with_suffix(".jpg")),
            "path": str(out), "timings": timings}


async def _final_bg(reel: dict, idx: int, version: int, rows_by_id: dict) -> None:
    lock = pipeline._final_locks.setdefault((reel["reel_id"], idx), asyncio.Lock())
    async with lock:
        cut = reel["cuts"][idx]
        if cut.get("version", 0) != version:
            return  # superseded by a newer edit
        try:
            res = await _render_version(reel, idx, "final", rows_by_id)
            if cut.get("version", 0) == version:
                cut["final"], cut["final_status"] = res, "done"
        except Exception as e:
            log.exception("edit final render failed")
            if cut.get("version", 0) == version:
                cut["final_status"], cut["final_error"] = "failed", str(e)[:300]
        pipeline.save(reel)


_edit_locks: dict[tuple[str, int], asyncio.Lock] = {}


@router.post("/v1/reels/{reel_id}/edit")
async def edit(reel_id: str, body: EditRequest):
    from .analysis import load_rows
    reel, cut = _reel_cut(reel_id, body.cut)
    idx = body.cut
    async with _edit_locks.setdefault((reel_id, idx), asyncio.Lock()):
        rows = await load_rows(immich(), reel["album_id"])
        for r in rows:
            if not r.get("analysis") and r.get("stale_analysis"):
                r["analysis"] = r["stale_analysis"]
        rows_by_id = {r["id"]: r for r in rows}
        try:
            clips, notes = validate_clips([c.model_dump() for c in body.clips], cut.get("clips") or [], rows_by_id)
        except ValueError as e:
            raise HTTPException(400, str(e))
        snapshot = {k: cut.get(k) for k in ("version", "title", "clips", "music", "music_mood", "cover_asset_id",
                                            "preview", "final", "final_status", "total_s")}
        snapshot["saved_at"] = time.time()
        versions = cut.setdefault("versions", [])
        versions.append(snapshot)
        version = int(cut.get("version", 0)) + 1
        cut["version"] = version
        cut["clips"] = clips
        if body.title:
            cut["title"] = body.title.strip()[:80]
        if body.music_mood:
            from .music import pick_track
            t = pick_track(body.music_mood.lower())
            if t:
                cut["music_mood"] = body.music_mood.lower()
                cut["music"] = {k: t.get(k) for k in ("file", "title", "bpm", "beat_offset", "attribution", "licence", "path")}
        if cut.get("cover_asset_id") not in {c["asset_id"] for c in clips}:
            cut["cover_asset_id"] = next((c["asset_id"] for c in clips if c["kind"] == "photo"), clips[0]["asset_id"])
        _, total = clip_timing(clips, _transitions(reel), xfade_s())
        cut["total_s"] = total
        cut["source"] = "edited"
        cut["final"], cut["final_status"] = None, "rendering"
        cut.pop("final_error", None)
        try:
            cut["preview"] = await _render_version(reel, idx, "preview", rows_by_id)
            cut.pop("preview_error", None)
        except Exception as e:
            log.exception("edit preview render failed")
            prev = versions.pop()
            for k, v in prev.items():
                if k != "saved_at":
                    cut[k] = v
            pipeline.save(reel)
            raise HTTPException(500, f"re-render failed: {str(e)[:200]}")
        pipeline.save(reel)
    t = asyncio.create_task(_final_bg(reel, idx, version, rows_by_id))
    _bg.add(t)
    t.add_done_callback(_bg.discard)
    final_path = pipeline.reels_dir() / reel_id / f"cut{idx}_v{version}_final.mp4"
    tm = cut["preview"].get("timings") or {}
    return {"reel_id": reel_id, "cut": idx, "version": version, "title": cut.get("title"),
            "preview_url": cut["preview"]["url"], "cover_url": cut["preview"]["cover_url"],
            "final_url": pipeline.public_url(final_path), "final_status": cut.get("final_status"),
            "duration_s": total, "notes": notes,
            "render": {"segments_cached": tm.get("segments_cached"), "segments": len(clips),
                       "total_ms": tm.get("total_ms"), "prep_ms": tm.get("prep_ms")},
            "edl_url": f"{base_url()}/v1/reels/{reel_id}/cuts/{idx}/edl"}
