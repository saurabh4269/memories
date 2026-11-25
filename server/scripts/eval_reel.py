"""Automatic rubric checks for one rendered reel + a contact sheet to score the visual criteria by eye.

Usage: uv run python scripts/eval_reel.py <reel.mp4> <plan.json> [--cut 0] [--analysis dump.json] [--out DIR]

plan.json may be a whole reel (with "cuts"), a single cut, or {"reel": {...}}. Clip metadata comes from
clip["meta"] (written by the pipeline) or, for older reels, from --analysis ({"analysis": {asset_id: {...}}}).
Checks follow docs/EDIT-RUBRIC.md "Automatable checks"; see memories.qa for the pure functions.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from PIL import Image, ImageDraw, ImageFont  # noqa: E402

from memories import qa  # noqa: E402


def probe(path: str) -> dict:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type,width,height,r_frame_rate",
                          "-of", "json", path], capture_output=True, text=True).stdout
    j = json.loads(out)
    v = next(s for s in j["streams"] if s["codec_type"] == "video")
    n, d = v["r_frame_rate"].split("/")
    return {"duration": float(j["format"]["duration"]), "w": v["width"], "h": v["height"], "fps": float(n) / float(d),
            "audio": any(s["codec_type"] == "audio" for s in j["streams"])}


def frame_at(path: str, t: float, width: int = 270) -> Image.Image:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", f"{max(0.0, t):.3f}", "-i", path, "-frames:v", "1",
                          "-vf", f"scale={width}:-2", "-f", "image2pipe", "-c:v", "png", "-"], capture_output=True).stdout
    import io
    if not raw and t > 0.3:
        return frame_at(path, t - 0.25, width)
    return Image.open(io.BytesIO(raw)).convert("RGB")


def audio_stats(path: str) -> dict:
    r = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-vn", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    out = {}
    for line in r.splitlines():
        if "max_volume" in line:
            out["max_db"] = float(line.split(":")[1].split()[0])
        if "mean_volume" in line:
            out["mean_db"] = float(line.split(":")[1].split()[0])
    return out


def contact_sheet(path: str, dur: float, out: Path, cuts: list[float], step: float = 1.0) -> Path:
    ts = [round(i * step, 2) for i in range(int((dur - 0.1) / step) + 1)]
    if dur - ts[-1] > 0.3:
        ts.append(round(dur - 0.15, 2))
    fw = 216
    frames = [frame_at(path, t, fw) for t in ts]
    fh = frames[0].size[1]
    cols = 6
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (fw + 6) + 6, rows * (fh + 28) + 6), (24, 24, 24))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 16)
    except Exception:
        font = ImageFont.load_default()
    sx, sy = fw / 1080, fh / 1920
    for i, (t, f) in enumerate(zip(ts, frames)):
        x, y = 6 + (i % cols) * (fw + 6), 6 + (i // cols) * (fh + 28)
        sheet.paste(f, (x, y + 22))
        fd = ImageDraw.Draw(sheet)
        fd.rectangle([x + 60 * sx, y + 22 + 250 * sy, x + 950 * sx, y + 22 + 1540 * sy], outline=(0, 255, 120))
        shot = sum(1 for c in cuts if c <= t + 1e-6)
        d.text((x + 2, y + 2), f"{t:.1f}s  #{shot}", fill=(255, 255, 0), font=font)
    sheet.save(out, "JPEG", quality=85)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mp4")
    ap.add_argument("plan")
    ap.add_argument("--cut", type=int, default=0)
    ap.add_argument("--analysis")
    ap.add_argument("--destination")
    ap.add_argument("--out")
    a = ap.parse_args()
    plan = json.loads(Path(a.plan).read_text())
    plan = plan.get("reel", plan)
    cut = plan["cuts"][a.cut] if "cuts" in plan else plan
    dest = a.destination or plan.get("destination") or cut.get("destination") or "wa_status"
    analysis = json.loads(Path(a.analysis).read_text()).get("analysis", {}) if a.analysis else {}
    for c in cut["clips"]:
        if not c.get("meta") and c["asset_id"] in analysis:
            an = analysis[c["asset_id"]]
            c["meta"] = {k: an.get(k) for k in ("people_count", "is_group", "quality", "moment_tag", "caption", "mood")}
    info = probe(a.mp4)
    out_dir = Path(a.out) if a.out else Path(a.mp4).with_suffix("")
    out_dir.mkdir(parents=True, exist_ok=True)
    durs = [qa.clip_len(c) for c in cut["clips"]]
    cuts = [0.0]
    for d in durs[:-1]:
        cuts.append(round(cuts[-1] + d, 3))
    # perceptual hash at every shot midpoint + every 0.5 s for adjacency/near-dup checks
    mids = [cuts[i] + durs[i] / 2 for i in range(len(durs))]
    hashes = [qa.dhash_img(frame_at(a.mp4, t, 160)) for t in mids]
    first = frame_at(a.mp4, 0.0, 160)
    report = qa.evaluate(cut, dest, info, hashes, first_luma=qa.mean_luma(first), audio=audio_stats(a.mp4))
    sheet = contact_sheet(a.mp4, info["duration"], out_dir / "contact.jpg", cuts)
    report["contact_sheet"] = str(sheet)
    (out_dir / "eval.json").write_text(json.dumps(report, indent=2, ensure_ascii=False))
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
