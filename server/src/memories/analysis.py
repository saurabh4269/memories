"""Shot analysis: Immich album -> gemma4 (6 images per call) -> cached per asset (sqlite + Immich metadata)."""
from __future__ import annotations

import asyncio
import concurrent.futures as cf
import io
import logging
import os
import subprocess
from datetime import datetime
from typing import Any

from PIL import Image, ImageDraw, ImageFont

from . import db
from .config import get_settings
from .immich import ImmichClient, parse_duration
from .render import ffmpeg_bin
from .sarvam import ANALYSIS_VERSION, SarvamClient
from .timing import event, stage

log = logging.getLogger("memories.analysis")
_pool = cf.ThreadPoolExecutor(max_workers=max(4, (os.cpu_count() or 4)))
_album_locks: dict[str, asyncio.Lock] = {}


# ---------------------------------------------------------------- album rows

def _iso(a: dict) -> str:
    return a.get("localDateTime") or a.get("fileCreatedAt") or ""


def to_row(a: dict) -> dict:
    ex = a.get("exifInfo") or {}
    w = a.get("width") or ex.get("exifImageWidth") or 0
    h = a.get("height") or ex.get("exifImageHeight") or 0
    if str(ex.get("orientation") or "") in ("5", "6", "7", "8"):
        w, h = h, w
    return {
        "id": a["id"], "type": a.get("type", "IMAGE"), "time": _iso(a),
        "duration": parse_duration(a.get("duration")) if a.get("type") == "VIDEO" else 0.0,
        "people": [p.get("name") for p in (a.get("people") or []) if p.get("name")],
        "person_ids": [p.get("id") for p in (a.get("people") or [])],
        "owner": a.get("ownerId"), "width": w, "height": h,
        "original_path": a.get("originalPath"), "has_metadata": a.get("hasMetadata", False),
        "file_name": a.get("originalFileName"),
    }


async def load_rows(immich: ImmichClient, album_id: str) -> list[dict]:
    assets = await immich.album_assets(album_id)
    rows = [to_row(a) for a in assets if a.get("type") in ("IMAGE", "VIDEO") and not a.get("isTrashed")]
    cached = db.get_analysis([r["id"] for r in rows])
    for r in rows:
        an = cached.get(r["id"])
        # cache version bump: re-analyse rows from older schemas (no activity/team_work)
        r["analysis"] = an if an and an.get("v", 1) >= ANALYSIS_VERSION else None
        if an and r["analysis"] is None:
            r["stale_analysis"] = an
    return rows


# ---------------------------------------------------------------- media prep

def video_source(immich: ImmichClient, row: dict) -> tuple[str, dict]:
    s = get_settings()
    op = row.get("original_path") or ""
    if s.immich_path_from and op.startswith(s.immich_path_from):
        local = s.immich_path_to + op[len(s.immich_path_from):]
        if os.path.exists(local):
            return local, {}
    url = immich.original_url(row["id"]) if s.video_source == "original" else immich.playback_url(row["id"])
    return url, {"x-api-key": immich.api_key}


def _header_args(h: dict) -> list[str]:
    return ["-headers", "".join(f"{k}: {v}\r\n" for k, v in h.items())] if h else []


def keyframe_jpeg(src: str, headers: dict, t: float, width: int = 480) -> bytes | None:
    cmd = [ffmpeg_bin(), "-hide_banner", "-loglevel", "error", *_header_args(headers), "-skip_frame", "nokey",
           "-ss", f"{t:.2f}", "-i", src, "-frames:v", "1", "-vf", f"scale={width}:-2", "-f", "image2pipe",
           "-c:v", "mjpeg", "-q:v", "4", "-"]
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=60)
        return r.stdout if r.returncode == 0 and r.stdout else None
    except Exception:
        return None


def contact_sheet(frames: list[tuple[float, bytes]], max_side: int = 768) -> bytes:
    ims = [(t, Image.open(io.BytesIO(b)).convert("RGB")) for t, b in frames]
    fw, fh = ims[0][1].size
    sheet = Image.new("RGB", (fw * 2, fh * 2), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype(str(get_settings().assets_dir / "fonts/NotoSans-Bold.ttf"), max(14, fh // 10))
    except Exception:
        font = ImageFont.load_default()
    for i, (t, im) in enumerate(ims[:4]):
        x, y = (i % 2) * fw, (i // 2) * fh
        sheet.paste(im.resize((fw, fh)), (x, y))
        draw.text((x + 8, y + 6), f"t={t:.1f}s", font=font, fill=(255, 255, 0), stroke_width=2, stroke_fill=(0, 0, 0))
    sheet.thumbnail((max_side, max_side))
    buf = io.BytesIO()
    sheet.save(buf, "JPEG", quality=80)
    return buf.getvalue()


def video_sheet(src: str, headers: dict, duration: float) -> tuple[bytes, list[float]] | None:
    d = max(duration, 1.0)
    ts = [round(d * f, 2) for f in (0.1, 0.35, 0.6, 0.85)]
    futs = [_pool.submit(keyframe_jpeg, src, headers, t) for t in ts]
    frames = [(t, f.result()) for t, f in zip(ts, futs)]
    frames = [(t, b) for t, b in frames if b]
    if not frames:
        return None
    while len(frames) < 4:
        frames.append(frames[-1])
    return contact_sheet(frames), ts


def shrink_jpeg(b: bytes, max_side: int = 768) -> bytes:
    im = Image.open(io.BytesIO(b)).convert("RGB")
    im.thumbnail((max_side, max_side))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=80)
    return buf.getvalue()


async def prep_input(immich: ImmichClient, row: dict) -> tuple[bytes, str] | None:
    """Returns (jpeg, note) for one asset."""
    try:
        if row["type"] == "VIDEO":
            src, hdr = video_source(immich, row)
            res = await asyncio.get_running_loop().run_in_executor(_pool, video_sheet, src, hdr, row["duration"])
            if res is None:
                # fallback: Immich still preview of the video
                b = await immich.preview(row["id"])
                return shrink_jpeg(b), f"video still ({row['duration']:.0f} s long), best_window within 0-{row['duration']:.0f}"
            sheet, ts = res
            return sheet, f"VIDEO CONTACT SHEET, duration {row['duration']:.1f} s, frames at {ts}"
        cache = get_settings().data_dir / "cache" / "preview" / f"{row['id']}.jpg"
        if cache.exists():
            b = cache.read_bytes()
        else:
            b = await immich.preview(row["id"])
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_bytes(b)  # reused by the renderer
        return await asyncio.get_running_loop().run_in_executor(_pool, shrink_jpeg, b), ""
    except Exception as e:
        log.warning("prep failed for %s: %s", row["id"], e)
        return None


# ---------------------------------------------------------------- dedupe

def find_duplicates(rows: list[dict], window_s: float = 3.0) -> dict[str, str]:
    """Map dup asset id -> kept asset id: same uploader + same type within a 3 s window (burst shots)."""
    dups: dict[str, str] = {}
    def ts(r):
        try:
            return datetime.fromisoformat(r["time"].replace("Z", "+00:00")).timestamp()
        except Exception:
            return None
    groups: dict[tuple, list[dict]] = {}
    for r in rows:
        groups.setdefault((r.get("owner"), r["type"]), []).append(r)
    for g in groups.values():
        g = sorted([r for r in g if ts(r) is not None], key=ts)
        kept = None
        for r in g:
            if kept is not None and r["type"] == "IMAGE" and ts(r) - ts(kept) <= window_s:
                dups[r["id"]] = kept["id"]
            else:
                kept = r
    return dups


# ---------------------------------------------------------------- main

async def analyse_album(immich: ImmichClient, sarvam: SarvamClient, album_id: str, *, batch: int | None = None,
                        concurrency: int | None = None, rows: list[dict] | None = None,
                        limit: int | None = None) -> dict[str, Any]:
    s = get_settings()
    batch = max(1, min(6, batch or s.analysis_batch))
    concurrency = concurrency or s.analysis_concurrency
    lock = _album_locks.setdefault(album_id, asyncio.Lock())
    async with lock:
        with stage("analysis_list"):
            rows = rows if rows is not None else await load_rows(immich, album_id)
        todo = [r for r in rows if not r.get("analysis")]
        # reuse analysis already stored in Immich metadata (e.g. by another server instance)
        if todo:
            with stage("analysis_metadata_lookup"):
                sem = asyncio.Semaphore(8)
                async def lookup(r):
                    if not r.get("has_metadata"):
                        return
                    async with sem:
                        try:
                            v = await immich.get_metadata(r["id"])
                        except Exception:
                            return
                    if isinstance(v, dict) and isinstance(v.get("analysis"), dict) and \
                            v["analysis"].get("v", 1) >= ANALYSIS_VERSION:
                        r["analysis"] = v["analysis"]
                        db.put_analysis(r["id"], album_id, v["analysis"])
                await asyncio.gather(*(lookup(r) for r in todo))
            todo = [r for r in todo if not r.get("analysis")]
        dups = find_duplicates(rows)
        to_call = [r for r in todo if r["id"] not in dups]
        if limit:
            to_call = to_call[:limit]
        stats = {"assets": len(rows), "cached": len(rows) - len(todo), "analysed": 0, "duplicates": 0,
                 "failed": 0, "calls": 0}
        if to_call:
            with stage("analysis_prep"):
                psem = asyncio.Semaphore(8)
                async def prep(r):
                    async with psem:
                        return r, await prep_input(immich, r)
                prepared = [(r, p) for r, p in await asyncio.gather(*(prep(r) for r in to_call)) if p]
            stats["failed"] += len(to_call) - len(prepared)
            batches = [prepared[i : i + batch] for i in range(0, len(prepared), batch)]
            csem = asyncio.Semaphore(concurrency)

            async def run_batch(b):
                async with csem:
                    try:
                        res = await sarvam.analyse_images([p[0] for _, p in b], [p[1] for _, p in b])
                    except Exception as e:
                        log.warning("vision batch failed: %s", e)
                        stats["failed"] += len(b)
                        return
                stats["calls"] += 1
                for (r, _), an in zip(b, res):
                    an["model"] = s.vision_model
                    r["analysis"] = an
                    db.put_analysis(r["id"], album_id, an)
                    stats["analysed"] += 1
                    asyncio.create_task(_write_metadata(immich, r["id"], an))

            with stage("analysis_vision"):
                await asyncio.gather(*(run_batch(b) for b in batches))
        by_id = {r["id"]: r for r in rows}
        for dup, kept in dups.items():
            r = by_id.get(dup)
            k = by_id.get(kept)
            if r is not None and not r.get("analysis") and k is not None and k.get("analysis"):
                an = {**k["analysis"], "dup_of": kept, "quality": max(1, int(k["analysis"].get("quality", 5)) - 1)}
                r["analysis"] = an
                db.put_analysis(dup, album_id, an)
                stats["duplicates"] += 1
        event("analysis", **stats)
        return {"stats": stats, "rows": rows}


async def _write_metadata(immich: ImmichClient, asset_id: str, analysis: dict) -> None:
    """Merge our analysis into the asset's "memories" metadata (keeps uploader fields set by the app)."""
    try:
        cur = await immich.get_metadata(asset_id)
        val = cur if isinstance(cur, dict) else {}
        val["analysis"] = analysis
        await immich.put_metadata(asset_id, val)
    except Exception as e:
        log.debug("metadata write failed for %s: %s", asset_id, e)


async def poller(immich: ImmichClient, sarvam: SarvamClient, interval: int, stop: asyncio.Event) -> None:
    """Analyse new assets of watched albums every `interval` seconds."""
    while not stop.is_set():
        for album_id in db.watched_albums():
            try:
                res = await analyse_album(immich, sarvam, album_id)
                if res["stats"]["analysed"]:
                    log.info("poller analysed %s new assets in %s", res["stats"]["analysed"], album_id)
            except Exception as e:
                log.warning("poller error for %s: %s", album_id, e)
        try:
            await asyncio.wait_for(stop.wait(), timeout=interval)
        except asyncio.TimeoutError:
            pass
