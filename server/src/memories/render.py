"""Fast reel renderer: per-clip normalized segments in parallel (ffmpeg), then xfade join + music.

Photos: Immich preview JPEG -> Pillow canvas (face/subject-aware crop, blurred fill) -> zoompan.
Videos: 720p playback stream with input seeking (-ss before -i), never decoding the whole file.
"""
from __future__ import annotations

import concurrent.futures as cf
import contextvars
import hashlib
import io
import logging
import shutil
import subprocess
import time
from dataclasses import dataclass, field, replace
from functools import lru_cache
from pathlib import Path
from typing import Any

from PIL import Image, ImageFilter, ImageEnhance, ImageOps

from .captions import caption_png, choose_position, render_caption  # noqa: F401
from .config import get_settings
from .timing import stage

log = logging.getLogger("memories.render")

XFADE = 0.25  # seconds per crossfade (§7.2: short)
TRANSITIONS = ["fade"]  # no gimmick transitions (§7.3)


@dataclass(frozen=True)
class Profile:
    name: str
    w: int
    h: int
    fps: int
    seg_crf: int = 20
    bitrate: str = "6M"
    x264_preset: str = "veryfast"
    seg_preset: str = "ultrafast"
    transitions: str = "xfade"  # xfade | cut


PROFILES = {
    "preview": Profile("preview", 540, 960, 24, seg_crf=26, bitrate="2500k", x264_preset="veryfast",
                       seg_preset="ultrafast", transitions="cut"),
    "final": Profile("final", 1080, 1920, 30, seg_crf=23, bitrate="6M", x264_preset="veryfast",
                     seg_preset="veryfast", transitions="cut"),
}


def profile_from(name: str, overrides: dict | None = None) -> Profile:
    """overrides: Flagsmith schema {"res":720,"fps":24,"transition":"cut","cuts":1} (applies to final; preview is
    capped at the same res) and/or legacy {"preview":{w,h,fps}, "final":{...}, "transitions":...}."""
    p = PROFILES.get(name, PROFILES["preview"])
    if overrides:
        tr = overrides.get("transition") or overrides.get("transitions")
        if tr in ("xfade", "cut"):
            p = replace(p, transitions=tr)
        res = overrides.get("res")
        if isinstance(res, (int, float)) and res >= 360:
            w = int(res) // 2 * 2
            if name == "final" or w < p.w:
                p = replace(p, w=w, h=int(round(w * 16 / 9)) // 2 * 2)
        fps = overrides.get("fps")
        if isinstance(fps, (int, float)) and 12 <= fps <= 60 and (name == "final" or fps < p.fps):
            p = replace(p, fps=int(fps))
    if overrides and overrides.get("transitions") in ("xfade", "cut"):
        p = replace(p, transitions=overrides["transitions"])
    o = (overrides or {}).get(name) if overrides else None
    if isinstance(o, dict):
        kw = {k: o[k] for k in ("w", "h", "fps", "seg_crf", "bitrate", "x264_preset", "seg_preset", "transitions") if k in o}
        try:
            p = replace(p, **kw)
        except Exception:
            pass
    return p


@dataclass
class SegmentSpec:
    """One clip ready for rendering. `source` is a local JPEG path (photo) or URL (video)."""
    asset_id: str
    kind: str  # "photo" | "video"
    duration: float  # seconds of output (incl. transition overlap)
    source: str
    in_s: float = 0.0
    caption: str = ""
    focus: tuple[float, float] = (0.5, 0.5)
    landscape: bool = False
    zoom_in: bool = True
    headers: dict = field(default_factory=dict)
    face_span: tuple[float, float] | None = None
    is_group: bool = False
    faces: tuple = ()  # normalised (x0, y0, x1, y1) face boxes in the SOURCE image
    caption_role: str = "label"  # title | label
    fade_out: float = 0.0  # seconds of fade to black at the end (closing card)
    zoom_to: float = 1.08


@lru_cache
def ffmpeg_bin() -> str:
    return shutil.which("ffmpeg") or "ffmpeg"


@lru_cache
def pick_encoder() -> str:
    s = get_settings()
    if s.video_encoder != "auto":
        return s.video_encoder
    try:
        out = subprocess.run([ffmpeg_bin(), "-hide_banner", "-encoders"], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return "libx264"
    if "h264_videotoolbox" in out:
        return "h264_videotoolbox"
    return "libx264"


def encoder_args(p: Profile, encoder: str | None = None) -> list[str]:
    enc = encoder or pick_encoder()
    if enc == "h264_videotoolbox":
        return ["-c:v", "h264_videotoolbox", "-b:v", p.bitrate, "-profile:v", "high", "-pix_fmt", "yuv420p"]
    return ["-c:v", "libx264", "-preset", p.x264_preset, "-crf", "23", "-maxrate", p.bitrate,
            "-bufsize", "12M", "-profile:v", "high", "-pix_fmt", "yuv420p"]


def seg_encoder_args(p: Profile) -> list[str]:
    return ["-c:v", "libx264", "-preset", p.seg_preset, "-crf", str(p.seg_crf), "-pix_fmt", "yuv420p",
            "-g", str(p.fps), "-bf", "0", "-video_track_timescale", "90000"]


def _header_args(headers: dict) -> list[str]:
    if not headers:
        return []
    return ["-headers", "".join(f"{k}: {v}\r\n" for k, v in headers.items())]


def redact(cmd: list[str]) -> str:
    out = []
    skip = False
    for c in cmd:
        if skip:
            out.append("'<redacted>'")
            skip = False
            continue
        out.append(c)
        if c == "-headers":
            skip = True
    return " ".join(out)


# ---------------- command builders (pure, unit tested) ----------------

def build_photo_segment_cmd(canvas: str, out: str, p: Profile, duration: float, caption_png_path: str | None,
                            zoom_in: bool = True, focus: tuple[float, float] = (0.5, 0.5), zoom_to: float = 1.08,
                            fade_out: float = 0.0) -> list[str]:
    """Ken Burns 1.00 -> zoom_to (or back) with the focus point (faces) held fixed, linear speed (§6.2-6.4)."""
    n = max(1, round(duration * p.fps))
    dz = max(0.0, zoom_to - 1.0)
    zexpr = f"1+{dz:.3f}*on/{n}" if zoom_in else f"{zoom_to:.3f}-{dz:.3f}*on/{n}"
    fx = min(max(focus[0], 0.0), 1.0)
    fy = min(max(focus[1], 0.0), 1.0)
    fade = f",fade=t=out:st={max(0.0, duration - fade_out):.3f}:d={fade_out:.3f}" if fade_out > 0 else ""
    vf = (f"[0:v]zoompan=z='{zexpr}':x='(iw-iw/zoom)*{fx:.3f}':y='(ih-ih/zoom)*{fy:.3f}':d={n}:s={p.w}x{p.h}:fps={p.fps},"
          f"setsar=1{fade},format=yuv420p")
    cmd = [ffmpeg_bin(), "-y", "-hide_banner", "-loglevel", "error", "-i", canvas]
    if caption_png_path:
        cmd += ["-i", caption_png_path]
        vf += "[base];[base][1:v]overlay=0:0:format=auto,format=yuv420p[v]"
    else:
        vf += "[v]"
    cmd += ["-filter_complex", vf, "-map", "[v]", "-frames:v", str(n), "-r", str(p.fps), "-an",
            *seg_encoder_args(p), out]
    return cmd


def build_video_segment_cmd(url: str, out: str, p: Profile, in_s: float, duration: float,
                            caption_png_path: str | None, landscape: bool = True, focus_x: float = 0.5,
                            headers: dict | None = None, fade_out: float = 0.0) -> list[str]:
    W, H = p.w, p.h
    bw, bh = max(16, W // 8 // 2 * 2), max(16, H // 8 // 2 * 2)
    if landscape:
        fh = int(H * 0.62) // 2 * 2
        fg = (f"scale=-2:{fh},crop='min(iw,{W})':ih:'(iw-ow)*{focus_x:.3f}':0")
    else:
        fg = f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H}"
    vf = (f"[0:v]fps={p.fps},split=2[a][b];"
          f"[a]scale={bw}:{bh}:force_original_aspect_ratio=increase,crop={bw}:{bh},boxblur=6:2,"
          f"scale={W}:{H},eq=brightness=-0.08[bg];"
          f"[b]{fg}[fg];"
          f"[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1,tpad=stop_mode=clone:stop_duration=3"
          + (f",fade=t=out:st={max(0.0, duration - fade_out):.3f}:d={fade_out:.3f}" if fade_out > 0 else "")
          + ",format=yuv420p")
    cmd = [ffmpeg_bin(), "-y", "-hide_banner", "-loglevel", "error",
           *_header_args(headers or {}),
           "-ss", f"{max(0.0, in_s):.3f}", "-t", f"{duration + 0.5:.3f}", "-i", url]
    if caption_png_path:
        cmd += ["-i", caption_png_path]
        vf += "[base];[base][1:v]overlay=0:0:format=auto,format=yuv420p[v]"
    else:
        vf += "[v]"
    cmd += ["-filter_complex", vf, "-map", "[v]", "-t", f"{duration:.3f}", "-r", str(p.fps), "-an",
            *seg_encoder_args(p), out]
    return cmd


def xfade_offsets(durations: list[float], t: float = XFADE) -> list[float]:
    """Offsets for chaining xfade: segment k (k>=1) starts fading at sum(d_j - t for j<k)."""
    offs = []
    acc = 0.0
    for d in durations[:-1]:
        acc += d - t
        offs.append(round(acc, 3))
    return offs


def build_join_cmd(segments: list[str], durations: list[float], out: str, p: Profile,
                   music: str | None, music_offset: float = 0.0, t: float = XFADE,
                   encoder: str | None = None) -> list[str]:
    n = len(segments)
    total = sum(durations) - t * (n - 1) if n > 1 else durations[0]
    cmd = [ffmpeg_bin(), "-y", "-hide_banner", "-loglevel", "error"]
    for s in segments:
        cmd += ["-i", s]
    parts: list[str] = []
    if n == 1:
        parts.append("[0:v]null[v]")
    else:
        prev = "[0:v]"
        for k, off in enumerate(xfade_offsets(durations, t), start=1):
            lab = "[v]" if k == n - 1 else f"[x{k}]"
            tr = TRANSITIONS[(k - 1) % len(TRANSITIONS)]
            parts.append(f"{prev}[{k}:v]xfade=transition={tr}:duration={t}:offset={off}{lab}")
            prev = lab
    if music:
        cmd += ["-ss", f"{music_offset:.3f}", "-i", music]
        fade_st = max(0.0, total - 1.2)
        parts.append(f"[{n}:a]atrim=0:{total:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=0.3,"
                     f"afade=t=out:st={fade_st:.3f}:d=1.2,volume=0.9[a]")
    cmd += ["-filter_complex", ";".join(parts), "-map", "[v]"]
    if music:
        cmd += ["-map", "[a]", "-c:a", "aac", "-b:a", "160k", "-ar", "44100"]
    cmd += ["-t", f"{total:.3f}", "-r", str(p.fps), *encoder_args(p, encoder), "-movflags", "+faststart", out]
    return cmd


def build_concat_cmd(list_file: str, total: float, out: str, p: Profile, music: str | None,
                     music_offset: float = 0.0) -> list[str]:
    """Hard cuts: concat demuxer with stream copy (segments share codec/fps/timebase) + music mux."""
    cmd = [ffmpeg_bin(), "-y", "-hide_banner", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", list_file]
    if music:
        fade_st = max(0.0, total - 1.2)
        cmd += ["-ss", f"{music_offset:.3f}", "-i", music, "-filter_complex",
                f"[1:a]atrim=0:{total:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=0.3,afade=t=out:st={fade_st:.3f}:d=1.2,volume=0.9[a]",
                "-map", "0:v", "-map", "[a]", "-c:a", "aac", "-b:a", "160k", "-ar", "44100"]
    cmd += ["-c:v", "copy", "-t", f"{total:.3f}", "-movflags", "+faststart", out]
    return cmd


# ---------------- photo canvas (Pillow) ----------------

def canvas_geometry(iw: int, ih: int, p: Profile, focus: tuple[float, float],
                    face_span: tuple[float, float] | None = None, is_group: bool = False) -> dict:
    """Decide cover-crop vs blur-fill and where the source lands on the 1.2x canvas.
    Returns {mode, crop (src px), fg (canvas px rect for blur mode), upscale (vs the output frame)}."""
    CW, CH = int(p.w * 1.2) // 2 * 2, int(p.h * 1.2) // 2 * 2
    target = CW / CH
    fx, fy = focus

    def crop_box(w: int, h: int, aspect: float, cx: float, cy: float) -> tuple[int, int, int, int]:
        if w / h > aspect:
            nw = int(h * aspect)
            x = int(min(max(cx * w - nw / 2, 0), w - nw))
            return (x, 0, x + nw, h)
        nh = int(w / aspect)
        y = int(min(max(cy * h - nh / 2, 0), h - nh))
        return (0, y, w, y + nh)

    crop_w_frac = min(1.0, (ih * target) / iw)
    can_crop = iw / ih <= 0.8
    if not can_crop and face_span is not None:
        can_crop = (face_span[1] - face_span[0]) <= crop_w_frac * 0.85
    elif not can_crop and face_span is None and not is_group:
        can_crop = True
    # bias the crop so the main faces sit ~1/3 from the top (headroom)
    cb = crop_box(iw, ih, target, fx, min(1.0, fy + 0.12))
    upscale = p.w / max(1, cb[2] - cb[0])
    if can_crop and upscale <= 1.5:
        return {"mode": "crop", "crop": cb, "canvas": (CW, CH), "upscale": round(upscale, 2)}
    src = crop_box(iw, ih, 4 / 5, fx, fy) if iw / ih > 0.95 else (0, 0, iw, ih)
    sw, sh = src[2] - src[0], src[3] - src[1]
    fw, fh = CW, int(sh * CW / sw)
    if fh > CH:
        fh = CH
        fw = int(sw * fh / sh)
    x, y = (CW - fw) // 2, (CH - fh) // 2
    return {"mode": "blur", "crop": src, "fg": (x, y, x + fw, y + fh), "canvas": (CW, CH),
            "upscale": round(p.w / 1.2 * fw / CW / max(1, sw), 2)}


def map_point(g: dict, iw: int, ih: int, x: float, y: float) -> tuple[float, float]:
    """Normalised source point -> normalised canvas point (≈ output frame at zoom 1.0)."""
    cx0, cy0, cx1, cy1 = g["crop"]
    u = (x * iw - cx0) / max(1, cx1 - cx0)
    v = (y * ih - cy0) / max(1, cy1 - cy0)
    if g["mode"] == "crop":
        return u, v
    CW, CH = g["canvas"]
    fx0, fy0, fx1, fy1 = g["fg"]
    return (fx0 + u * (fx1 - fx0)) / CW, (fy0 + v * (fy1 - fy0)) / CH


def make_photo_canvas(jpeg: bytes, p: Profile, focus: tuple[float, float], out: Path,
                      face_span: tuple[float, float] | None = None, is_group: bool = False) -> Path:
    """Compose a 1.2x-sized vertical canvas: cover-crop around the faces when it keeps everyone and needs
    <= 1.5x upscale; otherwise the full image (4:5 for landscape) over a blurred, darkened copy (§8.1-8.5)."""
    im = ImageOps.exif_transpose(Image.open(io.BytesIO(jpeg))).convert("RGB")
    g = canvas_geometry(im.size[0], im.size[1], p, focus, face_span, is_group)
    CW, CH = g["canvas"]
    if g["mode"] == "crop":
        canvas = im.crop(g["crop"]).resize((CW, CH), Image.LANCZOS)
    else:
        w, h = im.size
        bgc = (0, int((h - w * CH / CW) / 2), w, int((h + w * CH / CW) / 2)) if w / h < CW / CH else \
              (int((w - h * CW / CH) / 2), 0, int((w + h * CW / CH) / 2), h)
        bg = im.crop(bgc).resize((CW // 8, CH // 8), Image.BILINEAR)
        bg = bg.filter(ImageFilter.GaussianBlur(5)).resize((CW, CH), Image.BILINEAR)
        bg = ImageEnhance.Brightness(bg).enhance(0.6)
        x0, y0, x1, y1 = g["fg"]
        bg.paste(im.crop(g["crop"]).resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0))
        canvas = bg
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, "JPEG", quality=90)
    return out


def photo_layout(jpeg_path: str, p: Profile, spec: "SegmentSpec") -> tuple[tuple[float, float], list[tuple]]:
    """Ken Burns focus + face boxes in output-frame coordinates (normalised)."""
    with Image.open(jpeg_path) as im:
        iw, ih = ImageOps.exif_transpose(im).size if im.getexif().get(274, 1) in (5, 6, 7, 8) else im.size
    g = canvas_geometry(iw, ih, p, spec.focus, spec.face_span, spec.is_group)
    focus = map_point(g, iw, ih, *spec.focus)
    faces = []
    for (a, b, c, d) in spec.faces or ():
        x0, y0 = map_point(g, iw, ih, a, b)
        x1, y1 = map_point(g, iw, ih, c, d)
        faces.append((x0, y0, x1, y1))
    return focus, faces


# ---------------- orchestration ----------------

def _run(cmd: list[str], label: str) -> float:
    t0 = time.perf_counter()
    r = subprocess.run(cmd, capture_output=True, text=True)
    ms = (time.perf_counter() - t0) * 1000
    if r.returncode != 0:
        log.error("ffmpeg failed (%s): %s\n%s", label, redact(cmd), r.stderr[-1500:])
        raise RuntimeError(f"ffmpeg failed for {label}: {r.stderr[-400:]}")
    log.debug("ffmpeg %s %.0f ms", label, ms)
    return ms


def cache_dir() -> Path:
    d = get_settings().data_dir / "cache"
    d.mkdir(parents=True, exist_ok=True)
    return d


def segment_key(spec: SegmentSpec, p: Profile) -> str:
    raw = (f"{spec.asset_id}|{spec.kind}|{spec.in_s:.2f}|{spec.duration:.2f}|{p}|{spec.caption}|"
           f"{spec.focus[0]:.2f},{spec.focus[1]:.2f}|{spec.landscape}|{spec.zoom_in}|{spec.face_span}|{spec.is_group}|{spec.faces}|{spec.caption_role}|"
           f"{spec.fade_out}|{spec.zoom_to}|v4")
    return hashlib.sha1(raw.encode()).hexdigest()[:20]


def render_segment(spec: SegmentSpec, p: Profile) -> tuple[Path, float, bool, dict]:
    """Returns (path, ms, cached, caption_meta)."""
    out = cache_dir() / "seg" / f"{segment_key(spec, p)}.mp4"
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".tmp.mp4")
    cap, meta = caption_for(spec, p)
    if out.exists() and out.stat().st_size > 0:
        return out, 0.0, True, meta
    t0 = time.perf_counter()
    if spec.kind == "photo":
        canvas = cache_dir() / "canvas" / f"{spec.asset_id}_{p.w}x{p.h}_{spec.focus[0]:.2f}_{spec.focus[1]:.2f}_{spec.face_span}_{spec.is_group}_v2.jpg"
        if not canvas.exists():
            make_photo_canvas(Path(spec.source).read_bytes(), p, spec.focus, canvas, spec.face_span, spec.is_group)
        focus, _ = photo_layout(spec.source, p, spec)
        cmd = build_photo_segment_cmd(str(canvas), str(tmp), p, spec.duration, str(cap) if cap else None, spec.zoom_in,
                                      focus, spec.zoom_to, spec.fade_out)
    else:
        cmd = build_video_segment_cmd(spec.source, str(tmp), p, spec.in_s, spec.duration, str(cap) if cap else None,
                                      spec.landscape, spec.focus[0], spec.headers, spec.fade_out)
    _run(cmd, f"segment {spec.asset_id[:8]}")
    tmp.rename(out)
    return out, (time.perf_counter() - t0) * 1000, False, meta


def caption_for(spec: SegmentSpec, p: Profile) -> tuple[Path | None, dict]:
    """Caption PNG placed in the safe box, away from faces (§8.6, §9.5). meta is in 1080x1920 coordinates."""
    if not spec.caption:
        return None, {}
    if spec.kind == "photo":
        try:
            _, faces = photo_layout(spec.source, p, spec)
        except Exception:
            faces = []
    else:
        sy = spec.focus[1]
        faces = [(0.3, sy - 0.12, 0.7, sy + 0.12)] if spec.face_span is not None or spec.is_group else []
    pos = choose_position(spec.caption_role, faces)
    path, meta = render_caption(spec.caption, p.w, p.h, cache_dir() / "captions", spec.caption_role, pos)
    meta["faces"] = [[round(f[0] * 1080), round(f[1] * 1920), round(f[2] * 1080), round(f[3] * 1920)] for f in faces]
    return path, meta


def render_reel(specs: list[SegmentSpec], out: Path, p: Profile, music: str | None, music_offset: float = 0.0,
                workers: int | None = None, cover_index: int = 0) -> dict[str, Any]:
    """Render segments in parallel, join with xfades + music, write MP4 + JPEG cover. Returns timings."""
    import os
    workers = workers or get_settings().render_workers or (os.cpu_count() or 4)
    timings: dict[str, Any] = {}
    out.parent.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()
    results: list[tuple[Path, float, bool, dict] | None] = [None] * len(specs)
    with stage(f"render_segments_{p.name}"):
        with cf.ThreadPoolExecutor(max_workers=workers) as ex:
            futs = {ex.submit(contextvars.copy_context().run, render_segment, s, p): i for i, s in enumerate(specs)}
            for f in cf.as_completed(futs):
                results[futs[f]] = f.result()
    timings["segments_ms"] = round((time.perf_counter() - t0) * 1000)
    timings["segments_cached"] = sum(1 for r in results if r and r[2])
    seg_paths = [str(r[0]) for r in results if r]
    durations = [s.duration for s in specs]
    t1 = time.perf_counter()
    with stage(f"render_join_{p.name}"):
        if p.transitions == "cut":
            lf = out.with_suffix(".txt")
            lf.write_text("".join(f"file '{sp}'\n" for sp in seg_paths))
            _run(build_concat_cmd(str(lf), sum(durations), str(out), p, music, music_offset), "concat")
            seg_paths_done = True
        else:
            seg_paths_done = False
        cmd = build_join_cmd(seg_paths, durations, str(out), p, music, music_offset)
        try:
            if not seg_paths_done:
                _run(cmd, "join")
        except RuntimeError:
            if pick_encoder() != "libx264":
                log.warning("hardware encoder failed, retrying with libx264")
                _run(build_join_cmd(seg_paths, durations, str(out), p, music, music_offset, encoder="libx264"), "join-x264")
            else:
                raise
    timings["join_ms"] = round((time.perf_counter() - t1) * 1000)
    cover = out.with_suffix(".jpg")
    ci = min(max(cover_index, 0), len(seg_paths) - 1)
    try:
        _run([ffmpeg_bin(), "-y", "-hide_banner", "-loglevel", "error", "-ss", "0.4", "-i", seg_paths[ci],
              "-frames:v", "1", "-q:v", "3", str(cover)], "cover")
    except RuntimeError:
        pass
    caps, t = [], 0.0
    for spec, r in zip(specs, results):
        if r and r[3]:
            caps.append({**r[3], "t0": round(t, 2), "t1": round(t + spec.duration, 2)})
        t += spec.duration - (XFADE if p.transitions != "cut" else 0)
    timings["captions"] = caps
    timings["total_ms"] = round((time.perf_counter() - t0) * 1000)
    timings["encoder"] = pick_encoder()
    timings["transitions"] = p.transitions
    timings["duration_s"] = round(sum(durations) - (XFADE * (len(durations) - 1) if p.transitions != "cut" else 0), 2)
    return timings
