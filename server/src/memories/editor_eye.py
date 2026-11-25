"""Editor's eye: Claude looks at *every* item in an album and makes the cut.

This is a self-contained stage the director can call before rendering. It never
touches director.py / render.py / analysis.py state; it only needs local media
files, ffmpeg/ffprobe, Pillow, and an Anthropic API key.

Public interface (all sync, all JSON-serialisable in/out):

    inv    = inventory(media_dir_or_paths)                 -> list[Item]
    sheets = build_sheets(inv, out_dir)                    -> list[Sheet]
    rating = rate_and_tag(sheets, inv, client=None)        -> dict  (per-item scores/tags/focus/windows)
    plan   = plan_cut(rating, inv, music, sheets=sheets,
                      target_s=32, feedback=None)          -> dict  (ordered shots with beats/focus/fx)
    crit   = critique(frame_sheets, edl, rubric_md)        -> dict  (per-criterion scores + fixes)

Item ids are stable short codes ("P07" photo, "V12" video) so the model can
refer to tiles on the contact sheets. `music` is
{"duration": s, "bpm": f, "beats": [s...], "drop": s}.

Integration (for director.py later):
    from memories import editor_eye as ee
    inv = ee.inventory(paths); sheets = ee.build_sheets(inv, work/"sheets")
    rating = ee.rate_and_tag(sheets, inv); plan = ee.plan_cut(rating, inv, music, sheets=sheets)
    -> map plan["shots"] onto SegmentSpec (id -> asset, beats -> duration, focus -> crop focus,
       fx == "punch"/"ramp" -> Ken Burns / speed params), render, then
    crit = ee.critique(frame_sheets(out), edl, rubric) and re-plan with feedback=crit if any score < 8.
"""
from __future__ import annotations

import base64
import concurrent.futures as cf
import io
import json
import os
import re
import subprocess
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont, ImageOps

MODEL = os.environ.get("EDITOR_EYE_MODEL", "claude-opus-5-5")
PHOTO_EXT = {".jpg", ".jpeg", ".png", ".heic", ".webp"}
VIDEO_EXT = {".mp4", ".mov", ".m4v", ".webm"}
USAGE: list[dict] = []  # appended per API call: {"stage", "input_tokens", "output_tokens", "seconds"}

PRICE_IN, PRICE_OUT = 4.0, 20.0  # USD / MTok for claude-opus-5-5


@dataclass
class Item:
    id: str
    path: str
    kind: str  # "photo" | "video"
    width: int = 0
    height: int = 0
    duration: float = 0.0
    fps: float = 0.0
    taken: str = ""
    strip_times: list[float] = field(default_factory=list)


@dataclass
class Sheet:
    path: str
    kind: str
    ids: list[str]


# ---------------------------------------------------------------- inventory

def _probe(path: str) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height,r_frame_rate:stream_side_data=rotation:format=duration",
         "-of", "json", path], capture_output=True, text=True, check=True).stdout
    j = json.loads(out)
    s = (j.get("streams") or [{}])[0]
    w, h = int(s.get("width", 0)), int(s.get("height", 0))
    rot = 0
    for sd in s.get("side_data_list", []) or []:
        if "rotation" in sd:
            rot = int(sd["rotation"])
    if abs(rot) % 180 == 90:
        w, h = h, w
    num, _, den = (s.get("r_frame_rate") or "30/1").partition("/")
    fps = float(num) / float(den or 1) if float(den or 1) else 30.0
    return {"width": w, "height": h, "fps": fps, "duration": float(j.get("format", {}).get("duration", 0) or 0)}


def inventory(src: str | Path | list) -> list[Item]:
    paths = sorted(Path(src).iterdir()) if isinstance(src, (str, Path)) else [Path(p) for p in src]
    photos = [p for p in paths if p.suffix.lower() in PHOTO_EXT]
    videos = [p for p in paths if p.suffix.lower() in VIDEO_EXT]
    items: list[Item] = []
    for i, p in enumerate(photos, 1):
        with Image.open(p) as im:
            im = ImageOps.exif_transpose(im)
            items.append(Item(f"P{i:02d}", str(p), "photo", im.width, im.height, taken=p.stem))
    with cf.ThreadPoolExecutor(16) as ex:
        probes = list(ex.map(lambda p: _probe(str(p)), videos))
    for i, (p, pr) in enumerate(zip(videos, probes), 1):
        d = pr["duration"]
        times = [round((k + 0.5) * d / 6, 2) for k in range(6)]
        items.append(Item(f"V{i:02d}", str(p), "video", pr["width"], pr["height"], d, pr["fps"],
                          taken=p.stem, strip_times=times))
    return items


# ---------------------------------------------------------------- sheets

def _font(px: int):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
              "/System/Library/Fonts/Supplemental/Arial Bold.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, px)
    return ImageFont.load_default()


def _label(draw: ImageDraw.ImageDraw, xy, text, px=26):
    f = _font(px)
    x, y = xy
    bb = draw.textbbox((x, y), text, font=f)
    draw.rectangle((bb[0] - 4, bb[1] - 3, bb[2] + 4, bb[3] + 3), fill=(0, 0, 0))
    draw.text((x, y), text, font=f, fill=(255, 230, 0))


def _thumb(img: Image.Image, box: tuple[int, int]) -> Image.Image:
    img = img.convert("RGB")
    img.thumbnail(box, Image.LANCZOS)
    tile = Image.new("RGB", box, (24, 24, 24))
    tile.paste(img, ((box[0] - img.width) // 2, (box[1] - img.height) // 2))
    return tile


def video_frame(path: str, t: float, height: int = 480) -> Image.Image:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", f"{t:.3f}", "-i", path, "-frames:v", "1",
                          "-vf", f"scale=-2:{height}", "-f", "image2pipe", "-vcodec", "mjpeg", "-"],
                         capture_output=True, check=True).stdout
    return Image.open(io.BytesIO(raw))


def build_sheets(items: list[Item], out_dir: str | Path, photos_per_sheet: int = 20,
                 strips_per_sheet: int = 4) -> list[Sheet]:
    """Numbered contact sheets: photos in 5x4 grids; each video as a 6-frame strip with timestamps."""
    out = Path(out_dir); out.mkdir(parents=True, exist_ok=True)
    sheets: list[Sheet] = []
    photos = [i for i in items if i.kind == "photo"]
    videos = [i for i in items if i.kind == "video"]
    T = 300
    for s in range(0, len(photos), photos_per_sheet):
        chunk = photos[s:s + photos_per_sheet]
        cols = 5; rows = (len(chunk) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * T, rows * T), (10, 10, 10))
        d = ImageDraw.Draw(sheet)
        for k, it in enumerate(chunk):
            with Image.open(it.path) as im:
                im = ImageOps.exif_transpose(im)
                im.draft("RGB", (T * 2, T * 2))
                tile = _thumb(im, (T - 6, T - 6))
            x, y = (k % cols) * T + 3, (k // cols) * T + 3
            sheet.paste(tile, (x, y)); _label(d, (x + 6, y + 6), it.id)
        p = out / f"photos_{s // photos_per_sheet + 1:02d}.jpg"
        sheet.save(p, quality=85); sheets.append(Sheet(str(p), "photo", [c.id for c in chunk]))

    jobs = [(v, t) for v in videos for t in v.strip_times]
    with cf.ThreadPoolExecutor(16) as ex:
        frames = list(ex.map(lambda vt: _safe_frame(vt[0].path, vt[1]), jobs))
    fmap = {(v.id, t): f for (v, t), f in zip(jobs, frames)}
    FW, FH, LH = 240, 300, 34
    for s in range(0, len(videos), strips_per_sheet):
        chunk = videos[s:s + strips_per_sheet]
        sheet = Image.new("RGB", (6 * FW, len(chunk) * (FH + LH)), (10, 10, 10))
        d = ImageDraw.Draw(sheet)
        for r, v in enumerate(chunk):
            y0 = r * (FH + LH)
            _label(d, (6, y0 + 4), f"{v.id}  {v.duration:.1f}s  {int(round(v.fps))}fps  {'portrait' if v.height > v.width else 'landscape'}", 22)
            for k, t in enumerate(v.strip_times):
                f = fmap.get((v.id, t))
                if f is not None:
                    sheet.paste(_thumb(f, (FW - 4, FH - 4)), (k * FW + 2, y0 + LH))
                _label(d, (k * FW + 8, y0 + LH + FH - 30), f"t={t:.1f}s", 18)
        p = out / f"videos_{s // strips_per_sheet + 1:02d}.jpg"
        sheet.save(p, quality=85); sheets.append(Sheet(str(p), "video", [c.id for c in chunk]))
    return sheets


def _safe_frame(path, t):
    try:
        return video_frame(path, t)
    except Exception:
        return None


# ---------------------------------------------------------------- Claude plumbing

def _client():
    import anthropic
    return anthropic.Anthropic(max_retries=4)


def _img_block(path: str, max_side: int = 1568) -> dict:
    with Image.open(path) as im:
        im = im.convert("RGB")
        im.thumbnail((max_side, max_side), Image.LANCZOS)
        buf = io.BytesIO(); im.save(buf, "JPEG", quality=85)
    return {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
                                         "data": base64.b64encode(buf.getvalue()).decode()}}


def _parse_json(text: str) -> Any:
    m = re.search(r"```(?:json)?\s*(.*?)```", text, re.S)
    if m:
        text = m.group(1)
    start = min([i for i in (text.find("{"), text.find("[")) if i >= 0], default=0)
    return json.loads(text[start:text.rfind("}" if text[start] == "{" else "]") + 1])


def _ask(stage: str, system: str, content: list, client=None, max_tokens: int = 48000,
         effort: str = "high") -> Any:
    client = client or _client()
    t0 = time.time()
    with client.messages.stream(model=MODEL, max_tokens=max_tokens, system=system,
                                thinking={"type": "adaptive"}, output_config={"effort": effort},
                                messages=[{"role": "user", "content": content}]) as stream:
        msg = stream.get_final_message()
    if msg.stop_reason == "refusal":
        raise RuntimeError(f"{stage}: model refused")
    text = "".join(b.text for b in msg.content if b.type == "text")
    USAGE.append({"stage": stage, "input_tokens": msg.usage.input_tokens,
                  "output_tokens": msg.usage.output_tokens, "seconds": round(time.time() - t0, 1)})
    try:
        return _parse_json(text)
    except Exception as e:  # keep the raw text for debugging
        raise RuntimeError(f"{stage}: could not parse JSON ({e}): {text[:400]}")


def cost_usd() -> float:
    return sum(u["input_tokens"] * PRICE_IN + u["output_tokens"] * PRICE_OUT for u in USAGE) / 1e6


EDITOR_SYSTEM = """You are a senior documentary cinematographer and social-video editor cutting a 9:16 \
recap reel of a hackathon (Festive Hacks 2026 at BIEC Bengaluru, WeMakeDevs x WeAreDevelopers). \
The footage was shot by one member of a participating team on a phone. You have a ruthless eye: you \
reward real emotion, motion, faces, hands-on-keyboard detail, strong composition and storytelling; \
you punish blur, empty corridors, backs of heads, dull static wides, near-duplicates and bad exposure. \
The viewer is a developer scrolling Instagram/LinkedIn: the vibe is hacker/builder energy, not cute."""


def _inventory_text(items: list[Item]) -> str:
    rows = []
    for it in items:
        if it.kind == "photo":
            rows.append(f"{it.id} photo {it.width}x{it.height} {it.taken}")
        else:
            rows.append(f"{it.id} video {it.duration:.1f}s {int(round(it.fps))}fps "
                        f"{'portrait' if it.height > it.width else 'landscape'} {it.taken} strip@{it.strip_times}")
    return "\n".join(rows)


# ---------------------------------------------------------------- stage 1: rate & tag

RATE_SCHEMA_HINT = """Return ONLY JSON:
{"team": "who the user's team is (recurring people at laptops: clothing/looks, which ids)",
 "event_story": "2-3 sentences: what the footage shows across the day",
 "items": [
  {"id": "P01", "score": 1-10, "emotion": 1-10, "energy": 1-10, "composition": 1-10, "story": 1-10,
   "tags": ["arrival/venue"|"team building"|"coding close-up"|"laughter"|"stage/demo"|"sponsor booth"|
            "mascot/robot"|"crowd energy"|"night grind"|"group photo"|"judges/mentors"|"discussion/huddle"|"food/break"|"swag"|"signage"|"other"],
   "team": true/false (user's team visible), "faces": number of clearly visible faces,
   "shot_size": "wide"|"medium"|"close"|"detail",
   "desc": "<= 12 words, concrete",
   "dup_group": "short key shared by near-duplicates (same moment/pose/angle) or null",
   "focus": [x, y]  (0..1 of the frame: the point a 9:16 crop must keep, e.g. the main face/hands),
   "flaws": "blur / dark / tilted / empty / backs / none",
   "windows": [ {"start": s, "end": s, "motion": 1-10, "desc": "what moves"} ]  (videos only: the 1-3 best
               1.5-4 s windows with real motion; use the strip timestamps to locate them; [] for photos)
  }, ... one entry for EVERY id ... ]}"""


def rate_and_tag(sheets: list[Sheet], items: list[Item], client=None, extra_scores: dict | None = None,
                 context: str = "") -> dict:
    content: list = [{"type": "text", "text": "Album inventory (ids match the yellow labels on the sheets):\n"
                      + _inventory_text(items)}]
    for s in sheets:
        content.append({"type": "text", "text": f"Sheet {Path(s.path).name}: {', '.join(s.ids)}"})
        content.append(_img_block(s.path))
    if extra_scores:
        content.append({"type": "text", "text": "Aesthetic model scores (0-10, advisory): "
                        + json.dumps(extra_scores)})
    if context:
        content.append({"type": "text", "text": "Facts from the album owner (trust these):\n" + context})
    content.append({"type": "text", "text": "Look at every tile and every video strip. Identify the user's team "
                    "(the recurring people working at laptops), then rate and tag EVERY item.\n" + RATE_SCHEMA_HINT})
    res = _ask("rate_and_tag", EDITOR_SYSTEM, content, client=client)
    got = {r["id"] for r in res.get("items", [])}
    res["missing"] = [i.id for i in items if i.id not in got]
    return res


# ---------------------------------------------------------------- stage 2: cut list

DEFAULT_BRIEF = """  hook (strongest motion/emotion frame, teases the peak) -> venue/arrival -> team arrives -> heads-down building ->
  close-ups of code/hands -> energy (booths, mascot, crowd) -> stage/demo peak at ~70% -> team group shot to end."""

PLAN_HINT = """Return ONLY JSON:
{"concept": "one line",
 "shots": [
   {"id": "V07", "beats": int, "in": seconds (videos: source start; photos 0),
    "focus": [x, y] (0..1 of the source frame; what the 9:16 crop centres on),
    "zoom": "in"|"out" (photos: Ken Burns 1.00->1.08 toward focus, or reverse),
    "fx": "none"|"punch"|"ramp",   punch = hard 1.0->1.15 punch-in on the shot's 2nd beat;
                                   ramp = video plays 2x for its first half then 1x (only videos; use 120fps sources if possible)
    "role": "hook|establish|build|closeup|huddle|energy|peak|end",
    "why": "<= 10 words"} ...],
 "unused_good": ["ids rated >= 7 you left out and why (one line)"]}"""


def plan_cut(rating: dict, items: list[Item], music: dict, sheets: list[Sheet] | None = None,
             target_s: float = 32.0, feedback: dict | None = None, previous: dict | None = None,
             brief: str = DEFAULT_BRIEF, client=None) -> dict:
    beat = 60.0 / music["bpm"]
    beats = music["beats"]
    drop_idx = min(range(len(beats)), key=lambda i: abs(beats[i] - music["drop"]))
    n_beats = int(target_s / beat)
    rules = f"""Music: {music.get('label', 'instrumental')}, {music['bpm']:.1f} BPM (1 beat = {beat:.3f}s), \
{music['duration']:.1f}s long. The reel starts on beat 0. The DROP (hard energy hit) is at beat {drop_idx} \
({beats[drop_idx]:.2f}s). Total length must be {n_beats - 2}-{n_beats} beats ({target_s:.0f}s).

Cut a {target_s:.0f}s energetic hackathon recap (NO text overlays, NO captions: pictures and music only):
- 20-28 shots. Photos 2 beats (fast runs may use 1-beat photos, at most 6 of those), videos 3-6 beats with REAL motion.
- Story / content brief (OVERRIDES anything else):
{brief}
- The shot that starts exactly on beat {drop_idx} (sum of beats of all earlier shots == {drop_idx}) is the PEAK: the most
  intense moment allowed by the brief, ideally video with motion. Before the drop: build tension with a fast run of 1-2 beat
  shots. After: sustain energy, then end on the strongest allowed closing shot held 4-6 beats.
- Shots must be distinct: at most ONE shot per dup_group; never two similar shots adjacent; alternate wide/medium/close.
- Skip dull/flawed items (empty corridors, blur, backs of heads). Use as many DIFFERENT strong items as fit so good media
  isn't wasted: prefer covering many high-scoring items over repeating any. Each id at most once.
- 2-3 'punch' or 'ramp' moments total, on high-energy points (one right on the drop).
- Video 'in' must lie inside a rated window, and in + needed source seconds (beats*{beat:.3f}, doubled for the ramp half) <= duration.
- Landscape sources get cropped to 9:16: set focus on the subject so faces stay in frame."""
    content: list = [{"type": "text", "text": "Inventory:\n" + _inventory_text(items)},
                     {"type": "text", "text": "Your ratings:\n" + json.dumps(rating, ensure_ascii=False)}]
    if sheets:
        for s in sheets:
            content.append({"type": "text", "text": f"Sheet {Path(s.path).name}: {', '.join(s.ids)}"})
            content.append(_img_block(s.path, 1200))
    if previous and feedback:
        content.append({"type": "text", "text": "Your previous cut:\n" + json.dumps(previous, ensure_ascii=False)
                        + "\nA reviewer watched the render and said:\n" + json.dumps(feedback, ensure_ascii=False)
                        + "\nRevise the cut to fix every issue while keeping what works."})
    content.append({"type": "text", "text": rules + "\n" + PLAN_HINT})
    plan = _ask("plan_cut" if not feedback else "replan", EDITOR_SYSTEM, content, client=client)
    return validate_plan(plan, items, music, n_beats)


def validate_plan(plan: dict, items: list[Item], music: dict, n_beats: int) -> dict:
    """Deterministic guard rails: drop unknown/duplicate ids, clamp video ins, trim to length."""
    by_id = {i.id: i for i in items}
    beat = 60.0 / music["bpm"]
    seen, shots, total = set(), [], 0
    for s in plan.get("shots", []):
        it = by_id.get(s.get("id"))
        if not it or it.id in seen:
            continue
        b = max(1, int(s.get("beats", 2)))
        if total + b > n_beats:
            b = n_beats - total
            if b < 1:
                break
        s["beats"] = b
        fx = s.get("fx", "none")
        if it.kind == "video":
            need = b * beat * (1.5 if fx == "ramp" else 1.0) + 0.1
            s["in"] = float(max(0.0, min(float(s.get("in", 0) or 0), it.duration - need)))
            if it.duration < need:
                continue
        else:
            s["in"] = 0.0
            if fx == "ramp":
                s["fx"] = "none"
        fx_ = s.get("focus") or [0.5, 0.45]
        s["focus"] = [min(1, max(0, float(fx_[0]))), min(1, max(0, float(fx_[1])))]
        seen.add(it.id); shots.append(s); total += b
    plan["shots"] = shots
    plan["total_beats"] = total
    return plan


# ---------------------------------------------------------------- stage 3: critique

CRITIC_SYSTEM = """You are a demanding head of post-production reviewing a vertical hackathon recap reel \
before it ships. Score strictly against the rubric; 8 means genuinely good, 10 means best-in-class."""


def critique(frame_sheets: list[str], edl: dict, rubric_md: str, client=None, notes: str = "") -> dict:
    content: list = [{"type": "text", "text": "Rubric:\n" + rubric_md}]
    for p in frame_sheets:
        content.append({"type": "text", "text": f"Frame sheet {Path(p).name} (one frame every 0.5 s, timestamp on each tile):"})
        content.append(_img_block(p))
    content.append({"type": "text", "text": "EDL / metadata:\n" + json.dumps(edl, ensure_ascii=False) + "\n" + notes +
                    """\nScore criteria 1-10 (0-10 each). Return ONLY JSON:
{"scores": {"hook": n, "pacing": n, "variety": n, "framing": n, "captions": n, "story": n, "people": n,
            "music": n, "ending": n, "technical": n},
 "total": n, "hard_fail": false,
 "evidence": {"hook": "...", ...one short line each},
 "fixes": [ {"shot_index": i (0-based EDL index) or null, "issue": "...", "action": "replace with Pxx/Vxx | refocus x,y | retime | reorder | drop"} ],
 "verdict": "one line"}"""})
    return _ask("critique", CRITIC_SYSTEM, content, client=client, max_tokens=24000)


def make_frame_sheets(video: str, out_dir: str | Path, every: float = 0.5, per_sheet: int = 32) -> list[str]:
    """1 frame per `every` s, tiled 8 wide with timestamps. Returns sheet paths."""
    out = Path(out_dir); out.mkdir(parents=True, exist_ok=True)
    d = _probe(video)["duration"]
    times = [round(k * every, 2) for k in range(int(d / every) + 1) if k * every < d - 0.05]
    with cf.ThreadPoolExecutor(16) as ex:
        frames = list(ex.map(lambda t: _safe_frame(video, t), times))
    FW, FH = 180, 320
    paths = []
    for s in range(0, len(times), per_sheet):
        chunk = list(zip(times, frames))[s:s + per_sheet]
        cols = 8; rows = (len(chunk) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * FW, rows * FH), (0, 0, 0))
        dr = ImageDraw.Draw(sheet)
        for k, (t, f) in enumerate(chunk):
            x, y = (k % cols) * FW, (k // cols) * FH
            if f is not None:
                sheet.paste(_thumb(f, (FW - 2, FH - 2)), (x + 1, y + 1))
            _label(dr, (x + 5, y + 5), f"{t:.1f}s", 18)
        p = out / f"frames_{s // per_sheet + 1:02d}.jpg"
        sheet.save(p, quality=85); paths.append(str(p))
    return paths


def to_json(obj) -> Any:
    if isinstance(obj, list):
        return [to_json(o) for o in obj]
    return asdict(obj) if hasattr(obj, "__dataclass_fields__") else obj
