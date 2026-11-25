"""Reel jobs: prompt -> (voice) -> analysis (bounded) -> director -> preview renders -> speculative finals."""
from __future__ import annotations

import asyncio
import logging
import time
import uuid
from pathlib import Path
from typing import Any

from . import db, director, flags
from .analysis import analyse_album, load_rows, video_source
from .config import get_settings
from .immich import ImmichClient
from .render import XFADE, SegmentSpec, profile_from, render_reel
from .sarvam import SarvamClient
from .timing import event, new_trace, stage

log = logging.getLogger("memories.pipeline")

VOCAB = ["reel", "रील", "status", "स्टेटस", "story", "स्टोरी", "insta", "WhatsApp", "Diwali", "दिवाली", "aarti", "आरती",
         "rangoli", "रंगोली", "diya", "दीया", "phuljhadi", "फुलझड़ी", "mithai", "मिठाई", "Nani", "नानी", "Dadi", "दादी",
         "Nana", "Dada", "Mausi", "मौसी", "Bua", "Chacha", "mehendi", "मेहंदी", "sangeet", "संगीत", "haldi", "हल्दी",
         "baraat", "बारात", "pheras", "फेरे", "emotional", "family"]

_final_tasks: dict[str, asyncio.Task] = {}


def reels_dir() -> Path:
    d = get_settings().data_dir / "reels"
    d.mkdir(parents=True, exist_ok=True)
    return d


def public_url(path: Path) -> str:
    rel = path.relative_to(get_settings().data_dir)
    return f"{get_settings().public_base_url.rstrip('/')}/files/{rel.as_posix()}"


# ---------------------------------------------------------------- voice prompt

async def voice_prompt(sarvam: SarvamClient, audio: bytes, content_type: str, filename: str,
                       people: list[str]) -> dict:
    """Dictate (vocabulary + context + JSON intent) with saaras:v4 + keyterms as fallback."""
    vocab = [{"word": "रील", "sounds_like": ["व्हील"], "description": "short vertical video"}] + \
            [{"word": w} for w in dict.fromkeys(people + ["स्टेटस", "दिवाली", "नानी", "दादी", "मौसी"]) if w][:60]
    try:
        res = await sarvam.dictate(audio, content_type, filename, vocabulary=vocab,
                                   context="A family member describing the reel they want made from the shared family event album (Diwali, wedding, event).")
        return res
    except Exception as e:
        log.warning("dictate failed (%s), falling back to saaras:v4", e)
    r = await sarvam.transcribe(audio, content_type, filename, keyterms=list(dict.fromkeys(people + VOCAB))[:50])
    return {"transcript": r.get("transcript", ""), "language_code": r.get("language_code"), "engine": "saaras:v4"}


def probe_dims(src: str, headers: dict) -> list[int] | None:
    """Display width/height of a video (rotation applied)."""
    import json as _json
    import subprocess
    cmd = ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
           "stream=width,height:stream_side_data=rotation:stream_tags=rotate", "-of", "json"]
    if headers:
        cmd += ["-headers", "".join(f"{k}: {v}\r\n" for k, v in headers.items())]
    try:
        out = subprocess.run(cmd + [src], capture_output=True, text=True, timeout=30).stdout
        st = _json.loads(out)["streams"][0]
        w, h = int(st["width"]), int(st["height"])
        rot = 0
        for sd in st.get("side_data_list") or []:
            if "rotation" in sd:
                rot = int(float(sd["rotation"]))
        rot = rot or int((st.get("tags") or {}).get("rotate", 0) or 0)
        if abs(rot) % 180 == 90:
            w, h = h, w
        return [w, h]
    except Exception:
        return None


# ---------------------------------------------------------------- perceptual hash

def dhash(path: Path) -> int:
    from PIL import Image
    im = Image.open(path).convert("L").resize((9, 8), Image.BILINEAR)
    px = list(im.getdata())
    v = 0
    for y in range(8):
        for x in range(8):
            v = (v << 1) | (px[y * 9 + x] > px[y * 9 + x + 1])
    return v


def add_phashes(rows: list[dict]) -> None:
    cache = get_settings().data_dir / "cache" / "preview"
    for r in rows:
        if r["type"] != "IMAGE":
            continue
        h = db.kv_get("phash", r["id"])
        if h is None:
            p = cache / f"{r['id']}.jpg"
            if not p.exists():
                continue
            try:
                h = dhash(p)
            except Exception:
                continue
            db.kv_put("phash", r["id"], h)
        r["phash"] = h


# ---------------------------------------------------------------- spec building

FULL_MAX_SIDE = 2560


async def photo_source(immich: ImmichClient, r: dict, cache: Path, sem: asyncio.Semaphore) -> Path:
    """Large source for cropping (avoid > 1.5x upscale): local original JPEG, else Immich fullsize, else preview."""
    full = cache.parent / "full" / f"{r['id']}.jpg"
    if full.exists():
        return full
    full.parent.mkdir(parents=True, exist_ok=True)
    data: bytes | None = None
    s = get_settings()
    op = r.get("original_path") or ""
    if op.lower().endswith((".jpg", ".jpeg", ".png")) and s.immich_path_from and op.startswith(s.immich_path_from):
        local = Path(s.immich_path_to + op[len(s.immich_path_from):])
        if local.exists():
            data = local.read_bytes()
    if data is None:
        async with sem:
            try:
                data = await immich.preview(r["id"], size="fullsize")
            except Exception:
                data = None
    if data is None:
        p = cache / f"{r['id']}.jpg"
        if not p.exists():
            async with sem:
                p.write_bytes(await immich.preview(r["id"]))
        return p

    def shrink() -> None:
        from PIL import Image, ImageOps
        import io as _io
        im = ImageOps.exif_transpose(Image.open(_io.BytesIO(data))).convert("RGB")
        im.thumbnail((FULL_MAX_SIDE, FULL_MAX_SIDE))
        im.save(full, "JPEG", quality=92)
    await asyncio.to_thread(shrink)
    return full


async def build_specs(immich: ImmichClient, cut: dict, rows_by_id: dict[str, dict], profile_transitions: str) -> list[SegmentSpec]:
    cache = get_settings().data_dir / "cache" / "preview"
    cache.mkdir(parents=True, exist_ok=True)
    clips = cut["clips"]
    specs: list[SegmentSpec | None] = [None] * len(clips)
    sem = asyncio.Semaphore(8)

    async def one(i: int, c: dict):
        r = rows_by_id[c["asset_id"]]
        an = r.get("analysis") or {}
        base = c["out_s"] - c["in_s"] if c["kind"] == "video" else c["hold_s"]
        overlap = XFADE if (profile_transitions != "cut" and i < len(clips) - 1) else 0.0
        dur = round(base + overlap, 3)
        sc = an.get("subject_center") or [0.5, 0.5]
        focus = (float(sc[0]), float(sc[1]))
        last = i == len(clips) - 1
        fade_out = 0.5 if (last and cut.get("destination", "wa_status") == "wa_status") else 0.0
        role = "title" if c.get("title_card") or i == 0 else "label"
        if c["kind"] == "photo":
            p = await photo_source(immich, r, cache, sem)
            async with sem:
                faces = db.kv_get("faces", r["id"])
                if faces is None:
                    faces = await immich.faces(r["id"])
                    if faces:  # empty may mean "not processed yet": don't cache
                        db.kv_put("faces", r["id"], faces)
            span = None
            boxes: list[tuple] = []
            if faces:
                xs, ys = [], []
                for f in faces:
                    iw, ih = f.get("imageWidth") or 1, f.get("imageHeight") or 1
                    b = (f["boundingBoxX1"] / iw, f["boundingBoxY1"] / ih, f["boundingBoxX2"] / iw, f["boundingBoxY2"] / ih)
                    if (b[2] - b[0]) < 0.02:  # tiny background faces don't steer framing
                        continue
                    boxes.append(tuple(round(v, 3) for v in b))
                    xs += [b[0], b[2]]
                    ys += [b[1], b[3]]
                if xs:
                    focus = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)
                    span = (round(min(xs), 3), round(max(xs), 3))
            photo_idx = sum(1 for cc in clips[:i] if cc["kind"] == "photo")
            specs[i] = SegmentSpec(r["id"], "photo", dur, str(p), caption=c.get("caption", ""), focus=focus,
                                   zoom_in=(photo_idx % 2 == 0) or last, face_span=span,
                                   is_group=bool(an.get("is_group")), faces=tuple(boxes), caption_role=role,
                                   fade_out=fade_out, zoom_to=1.05 if last else 1.08)
        else:
            src, hdr = video_source(immich, r)
            dims = db.kv_get("vdims", r["id"])
            if dims is None:
                dims = await asyncio.to_thread(probe_dims, src, hdr)
                if dims:
                    db.kv_put("vdims", r["id"], dims)
            w, h = dims or (r.get("width") or 16, r.get("height") or 9)
            landscape = w > h
            specs[i] = SegmentSpec(r["id"], "video", dur, src, in_s=c["in_s"], caption=c.get("caption", ""),
                                   focus=focus, landscape=landscape, headers=hdr, caption_role=role,
                                   fade_out=fade_out, is_group=bool(an.get("is_group")),
                                   face_span=(0.3, 0.7) if int(an.get("people_count") or 0) > 0 else None)

    await asyncio.gather(*(one(i, c) for i, c in enumerate(clips)))
    return [s for s in specs if s is not None]


async def render_cut(immich: ImmichClient, reel: dict, idx: int, profile_name: str, rows_by_id: dict) -> dict:
    cut = reel["cuts"][idx]
    p = profile_from(profile_name, reel.get("render_overrides"))
    t0 = time.perf_counter()
    specs = await build_specs(immich, cut, rows_by_id, p.transitions)
    prep_ms = round((time.perf_counter() - t0) * 1000)
    out = reels_dir() / reel["reel_id"] / f"cut{idx}_{profile_name}.mp4"
    music = (cut.get("music") or {})
    ci = next((i for i, c in enumerate(cut["clips"]) if c["asset_id"] == cut.get("cover_asset_id")), 0)
    timings = await asyncio.to_thread(render_reel, specs, out, p, music.get("path"),
                                      float(music.get("beat_offset") or 0.0), None, ci)
    timings["prep_ms"] = prep_ms
    if timings.get("captions") is not None:
        cut["captions"] = timings.pop("captions")
    cut["crossfades"] = timings.get("crossfades", 0)
    timings["profile"] = {"name": p.name, "w": p.w, "h": p.h, "fps": p.fps}
    return {"url": public_url(out), "cover_url": public_url(out.with_suffix(".jpg")), "path": str(out), "timings": timings}


# ---------------------------------------------------------------- main job

_mem: dict[str, dict] = {}


def save(reel: dict) -> None:
    _mem[reel["reel_id"]] = reel
    db.kv_put("reel", reel["reel_id"], {k: v for k, v in reel.items() if not k.startswith("_")})


def load(reel_id: str) -> dict | None:
    if reel_id in _mem:
        return _mem[reel_id]
    r = db.kv_get("reel", reel_id)
    if r:
        _mem[reel_id] = r
    return r


def public_cut(c: dict) -> dict:
    return {
        "title": c["title"], "why": c["why"], "source": c.get("source"), "total_s": c.get("total_s"),
        "music": {k: (c.get("music") or {}).get(k) for k in ("title", "bpm", "attribution")},
        "cover_asset_id": c.get("cover_asset_id"), "caption_language": c.get("caption_language"),
        "clips": [{k: v for k, v in cl.items() if k != "max_len"} for cl in c["clips"]],
        "preview_url": (c.get("preview") or {}).get("url"), "cover_url": (c.get("preview") or {}).get("cover_url"),
        "final_url": (c.get("final") or {}).get("url"), "final_status": c.get("final_status", "pending"),
        "captions": c.get("captions"), "destination": c.get("destination"),
    }


def public_reel(reel: dict) -> dict:
    return {
        "reel_id": reel["reel_id"], "album_id": reel["album_id"], "status": reel.get("status"),
        "prompt": reel.get("prompt"), "destination": reel.get("destination"), "member_name": reel.get("member_name"),
        "mode": reel.get("mode", "normal"), "strategy": reel.get("strategy"), "label": reel.get("label"),
        "cuts": [public_cut(c) for c in reel.get("cuts", [])],
        "timings": reel.get("timings", {}), "trace": reel.get("trace", {}), "error": reel.get("error"),
        "team": reel.get("team"),
    }


async def create_reel(immich: ImmichClient, sarvam: SarvamClient, *, album_id: str, prompt: str | None,
                      destination: str = "wa_status", member_name: str | None = None, language: str | None = None,
                      audio: tuple[bytes, str, str] | None = None, analysis_budget_s: float = 45.0,
                      speculative_final: bool = True) -> dict:
    trace = new_trace()
    t_start = time.perf_counter()
    fl_task = asyncio.create_task(asyncio.to_thread(flags.identity_flags, member_name or "anonymous"))
    strat_task = asyncio.create_task(asyncio.to_thread(flags.director_strategy, member_name))
    fl = await fl_task
    lite = flags.ml_lite(fl)
    reel: dict[str, Any] = {
        "reel_id": uuid.uuid4().hex[:12], "album_id": album_id, "prompt": prompt or "", "destination": destination,
        "member_name": member_name, "language": language, "status": "planning", "mode": flags.mode(fl),
        "render_overrides": flags.render_overrides(fl), "created": time.time(),
    }
    db.watch_album(album_id)
    with stage("album_list"):
        rows = await load_rows(immich, album_id)
        try:
            album = await immich.get_album(album_id)
        except Exception:
            album = {}
    album_name = album.get("albumName", "")
    people = sorted({n for r in rows for n in r.get("people", [])})
    if audio:
        with stage("voice_prompt"):
            vp = await voice_prompt(sarvam, audio[0], audio[1], audio[2], people)
        reel["voice"] = vp
        spoken = vp.get("intent_text") or vp.get("text") or vp.get("transcript") or ""
        reel["prompt"] = prompt = ((prompt or "") + " " + spoken).strip()
    # bounded analysis of anything new (poller normally did this already)
    if any(not r.get("analysis") for r in rows):
        with stage("analysis"):
            try:
                res = await asyncio.wait_for(
                    analyse_album(immich, sarvam, album_id, rows=rows,
                                  batch=(lite or {}).get("analysis_batch")), timeout=analysis_budget_s)
                reel["analysis_stats"] = res["stats"]
            except asyncio.TimeoutError:
                event("analysis budget exceeded; planning with partial analysis")
    for r in rows:  # analysis budget ran out for some rows: plan with their older-schema analysis
        if not r.get("analysis") and r.get("stale_analysis"):
            r["analysis"] = r["stale_analysis"]
    rows_by_id = {r["id"]: r for r in rows}
    with stage("phash"):
        await asyncio.to_thread(add_phashes, rows)
    try:  # optional Facet scores (memories.facet_scores, another agent's module)
        from .facet_scores import load_scores
        fs = await asyncio.to_thread(load_scores, album_id)
        for r in rows:
            if fs and r["id"] in fs:
                r["facet"] = fs[r["id"]]
                sb = (fs[r["id"]] or {}).get("subject_box")
                an = r.get("analysis")
                if an and sb and len(sb) == 4 and max(sb) <= 1.0 and not r.get("person_ids"):
                    an["subject_center"] = [(sb[0] + sb[2]) / 2, (sb[1] + sb[3]) / 2]
    except Exception as e:
        log.info("facet scores unavailable: %s", e)
    with stage("team"):
        try:
            from . import team
            reel["team"] = await team.annotate(immich, album_id, rows)
        except Exception as e:
            log.warning("team scoring failed: %s", e)
    drows = director.asset_rows(rows)
    strategy, sinfo = await strat_task
    reel["strategy"] = strategy
    reel["strategy_info"] = sinfo
    with stage("plan"):
        cuts, info = None, {}
        if strategy == "agentic":
            try:
                from .agentic import plan_agentic
                cuts, info = await plan_agentic(sarvam, immich, album_id, drows, prompt or "", destination,
                                                member_name, language, album_name)
            except Exception as e:
                log.warning("agentic director failed, falling back: %s", e)
                event("agentic failed, falling back to single_shot", error=str(e)[:200])
                reel["strategy"] = "single_shot (fallback)"
                cuts = None
        if not cuts:
            cuts, info = await director.plan(sarvam, drows, prompt or "", destination, member_name, language, album_name)
    max_cuts = (reel.get("render_overrides") or {}).get("cuts")
    if isinstance(max_cuts, int) and 1 <= max_cuts < len(cuts):
        cuts = cuts[:max_cuts]
    reel["cuts"] = cuts
    reel["label"] = info.get("label")
    reel["plan_info"] = {k: v for k, v in info.items() if k != "raw"}
    reel["status"] = "rendering_preview"
    save(reel)
    with stage("render_preview"):
        results = await asyncio.gather(*(render_cut(immich, reel, i, "preview", rows_by_id) for i in range(len(cuts))),
                                       return_exceptions=True)
    for c, r in zip(cuts, results):
        if isinstance(r, Exception):
            log.exception("preview render failed", exc_info=r)
            c["preview_error"] = str(r)[:300]
        else:
            c["preview"] = r
    reel["status"] = "ready"
    reel["timings"] = {
        "total_ms": round((time.perf_counter() - t_start) * 1000), "stages_ms": trace["stages"],
        "sarvam_calls": trace["calls"],
        "render": {f"cut{i}_preview": (c.get("preview") or {}).get("timings") for i, c in enumerate(cuts)},
    }
    reel["trace"] = {"events": trace["events"], "plan": reel["plan_info"], "strategy": reel["strategy_info"],
                     "agent": info.get("tool_trace")}
    save(reel)
    if speculative_final:
        _final_tasks[reel["reel_id"]] = asyncio.create_task(_speculative_finals(immich, reel, rows_by_id))
    return reel


async def _speculative_finals(immich: ImmichClient, reel: dict, rows_by_id: dict) -> None:
    for i in range(len(reel["cuts"])):
        await render_final(immich, reel, i, rows_by_id)


_final_locks: dict[tuple[str, int], asyncio.Lock] = {}


async def render_final(immich: ImmichClient, reel: dict, idx: int, rows_by_id: dict | None = None) -> dict:
    lock = _final_locks.setdefault((reel["reel_id"], idx), asyncio.Lock())
    async with lock:
        cut = reel["cuts"][idx]
        if cut.get("final_status") == "done" and cut.get("final"):
            return cut["final"]
        cut["final_status"] = "rendering"
        save(reel)
        try:
            if rows_by_id is None:
                rows_by_id = {r["id"]: r for r in await load_rows(immich, reel["album_id"])}
            res = await render_cut(immich, reel, idx, "final", rows_by_id)
            cut["final"] = res
            cut["final_status"] = "done"
            reel.setdefault("timings", {}).setdefault("render", {})[f"cut{idx}_final"] = res["timings"]
        except Exception as e:
            log.exception("final render failed")
            cut["final_status"] = "failed"
            cut["final_error"] = str(e)[:300]
        save(reel)
        return cut.get("final") or {}
