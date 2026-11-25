#!/usr/bin/env python3
"""Make the best recap reel from an album folder with Claude as the editor's eye.

Runs on the VM (ffmpeg + 16 cores):
    python make_best_reel.py --media /opt/media/hackathon --work /opt/editor-eye/work \
        --music /opt/editor-eye/music_eleven.mp3 --out /srv/director/reels/best-hackathon

Stages are cached in --work (inventory.json, rating.json, plan_vN.json ...), so re-runs are cheap.
Needs ANTHROPIC_API_KEY (read from --keys env file if not set; values are never printed).
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from memories import editor_eye as ee
except ImportError:  # flat deployment next to this script
    import editor_eye as ee

W, H, FPS = 1080, 1920, 30
GRADE = ("eq=contrast=1.07:saturation=1.08:gamma=0.98,"
         "colorbalance=rs=0.025:bs=-0.025:rm=0.02:bm=-0.02,"
         "vignette=angle=PI/5")

BRIEF = """ONLY people building: hackers coding at laptops, discussing around screens, hands on keyboards, heads-down focus,
  teams huddled. At most ONE short wide establishing shot of the hacking hall full of people building (opener or 2nd shot).
  EXCLUDE booths, sponsor stalls, corridors, walking crowds, mascot/robot, stage/talk/demo scenes (there were no demos yet).
  The three people standing together (incl. a man in a black t-shirt holding a mic next to two others) are the HACKATHON
  JUDGES, not the team: at most one shot of them as a 'judges on the floor' moment, never the last shot.
  Feature the user's team generously. End on the most intense team-building shot (not the judges).
  Landscape videos get upscaled 1.78x when cropped to 9:16, so prefer portrait videos and photos; landscape video at most 2 shots."""

CONTEXT = """- Event: Festive Hacks 2026, BIEC Bengaluru (WeMakeDevs x WeAreDevelopers). No demos had happened yet.
- Three people standing together (one man in a black t-shirt holding a mic, next to two others) are the HACKATHON JUDGES, not the team.
- The user's team are the recurring people working at laptops together."""


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def load_env(path: str):
    if path and os.path.exists(path):
        for line in open(path):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def cached(path: Path, fn):
    if path.exists():
        return json.loads(path.read_text())
    res = fn()
    path.write_text(json.dumps(res, indent=1, ensure_ascii=False))
    return res


# ---------------------------------------------------------------- music

def analyse_music(path: str, drop_hint: float) -> dict:
    import librosa
    y, sr = librosa.load(path, sr=22050, mono=True)
    dur = len(y) / sr
    tempo, frames = librosa.beat.beat_track(y=y, sr=sr, units="frames")
    bt = librosa.frames_to_time(frames, sr=sr)
    bpm = float(np.atleast_1d(tempo)[0])
    # librosa's tempo is quantised (e.g. 123.05 for a 124 BPM track): fit period + phase to the detected beats
    period0 = 60.0 / bpm
    k = np.round((bt - bt[0]) / period0)
    (period, anchor), *_ = np.linalg.lstsq(np.vstack([k, np.ones_like(k)]).T, bt, rcond=None)
    period, anchor = float(period), float(anchor)
    bpm = 60.0 / period
    anchor = anchor % period
    grid = [anchor + k * period for k in range(int((dur - anchor) / period) + 1)]
    # drop = biggest RMS jump within +-5 s of the hint, snapped to the grid
    hop = 512
    rms = librosa.feature.rms(y=y, hop_length=hop)[0]
    t = librosa.frames_to_time(np.arange(len(rms)), sr=sr, hop_length=hop)
    win = int(0.5 * sr / hop)
    best, best_t = -1e9, drop_hint
    for g in grid:
        if abs(g - drop_hint) > 5:
            continue
        i = int(np.searchsorted(t, g))
        if i - win < 0 or i + win >= len(rms):
            continue
        jump = rms[i:i + win].mean() - rms[i - win:i].mean()
        if jump > best:
            best, best_t = jump, g
    return {"duration": dur, "bpm": bpm, "beats": [round(b - anchor, 4) for b in grid],
            "offset": anchor, "drop": round(best_t - anchor, 3), "drop_abs": best_t,
            "label": "dark synthwave / driving techno instrumental (AI-generated, ElevenLabs Music)"}


# ---------------------------------------------------------------- rendering

def _encode_args(n_frames: int) -> list[str]:
    return ["-frames:v", str(n_frames), "-r", str(FPS), "-c:v", "libx264", "-preset", "medium", "-crf", "17",
            "-pix_fmt", "yuv420p", "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
            "-an", "-movflags", "+faststart"]


def render_photo(shot: dict, item: dict, n: int, out: str, beat_frames: int):
    im = ImageOps.exif_transpose(Image.open(item["path"])).convert("RGB")
    iw, ih = im.size
    fx, fy = shot["focus"]
    # largest 9:16 window, centred on focus (with headroom: focus sits a bit above centre)
    cw = min(iw, ih * 9 / 16); ch = cw * 16 / 9
    cx = min(max(fx * iw, cw / 2), iw - cw / 2)
    cy = min(max(fy * ih + ch * 0.08, ch / 2), ih - ch / 2)
    box = (cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2)
    bw = int(min(cw, W * 1.3)); bh = int(bw * 16 / 9)
    base = im.resize((bw, bh), Image.LANCZOS, box=box)
    # focus inside base coords
    pfx = (fx * iw - box[0]) / cw; pfy = (fy * ih - box[1]) / ch
    z0, z1 = (1.0, 1.08) if shot.get("zoom", "in") == "in" else (1.08, 1.0)
    punch_at = beat_frames if shot.get("fx") == "punch" and n > beat_frames else None
    cmd = ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
           "-i", "-", "-vf", GRADE] + _encode_args(n) + [out]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for i in range(n):
        prog = i / max(1, n - 1)
        prog = prog * prog * (3 - 2 * prog) * 0.5 + prog * 0.5  # gentle ease
        z = z0 + (z1 - z0) * prog
        if punch_at is not None and i >= punch_at:
            z *= 1.15
        ww, hh = bw / z, bh / z
        # drift toward focus as we zoom in
        tx = bw / 2 + (pfx * bw - bw / 2) * (1 - 1 / z) * 1.6
        ty = bh / 2 + (pfy * bh - bh / 2) * (1 - 1 / z) * 1.6
        tx = min(max(tx, ww / 2), bw - ww / 2); ty = min(max(ty, hh / 2), bh - hh / 2)
        fr = base.transform((W, H), Image.EXTENT, (tx - ww / 2, ty - hh / 2, tx + ww / 2, ty + hh / 2),
                            Image.BICUBIC)
        p.stdin.write(fr.tobytes())
    p.stdin.close()
    if p.wait() != 0:
        raise RuntimeError(f"photo render failed {shot['id']}")


def render_video(shot: dict, item: dict, n: int, out: str, beat_frames: int):
    dur = n / FPS
    fx, fy = shot["focus"]
    portrait = item["height"] >= item["width"]
    if portrait:
        geo = f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H}"
    else:
        sh = H; sw = int(round(item["width"] * H / item["height"] / 2) * 2)
        x = int(min(max(fx * sw - W / 2, 0), sw - W))
        geo = f"scale={sw}:{sh}:flags=lanczos,crop={W}:{H}:{x}:0"
    fxname = shot.get("fx", "none")
    pieces = []  # (src_start, out_dur, speed, zoom)
    if fxname == "ramp":
        h1 = round(n / 2) / FPS; h2 = dur - h1
        if item["fps"] >= 100:
            pieces = [(0.0, h1, 1.0, 1.0), (h1, h2, 0.4, 1.0)]       # real-time into smooth slow-mo
        else:
            pieces = [(0.0, h1, 2.0, 1.0), (h1 * 2, h2, 1.0, 1.0)]   # fast into real-time
    elif fxname == "punch" and n > beat_frames:
        b = beat_frames / FPS
        pieces = [(0.0, b, 1.0, 1.0), (b, dur - b, 1.0, 1.15)]
    else:
        pieces = [(0.0, dur, 1.0, 1.0)]
    need = sum(d * s for _, d, s, _ in pieces) + 0.2
    parts, labels = [], []
    for k, (st, d, sp, z) in enumerate(pieces):
        zf = "" if z == 1.0 else f",scale={int(W * z) // 2 * 2}:{int(H * z) // 2 * 2},crop={W}:{H}"
        parts.append(f"[0:v]trim=start={st:.4f}:duration={d * sp:.4f},setpts=(PTS-STARTPTS)/{sp},"
                     f"{geo}{zf},fps={FPS},setsar=1[p{k}]")
        labels.append(f"[p{k}]")
    fc = ";".join(parts) + f";{''.join(labels)}concat=n={len(labels)}:v=1:a=0,{GRADE},tpad=stop_mode=clone:stop_duration=1[v]"
    cmd = ["ffmpeg", "-y", "-v", "error", "-ss", f"{shot['in']:.3f}", "-t", f"{need:.3f}", "-i", item["path"],
           "-filter_complex", fc, "-map", "[v]"] + _encode_args(n) + [out]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"video render failed {shot['id']}: {r.stderr[-600:]}")


def render(plan: dict, items: dict, music: dict, music_path: str, work: Path, tag: str) -> tuple[Path, dict]:
    seg_dir = work / f"seg_{tag}"; seg_dir.mkdir(parents=True, exist_ok=True)
    beats = music["beats"]
    period = 60.0 / music["bpm"]
    beat_frames = int(round(period * FPS))
    # cut frames on the beat grid (grid starts at reel t=0)
    cuts, k = [0], 0
    for s in plan["shots"]:
        k += s["beats"]
        t = beats[k] if k < len(beats) else beats[-1] + (k - len(beats) + 1) * period
        cuts.append(int(round(t * FPS)))
    jobs = []
    for i, s in enumerate(plan["shots"]):
        n = cuts[i + 1] - cuts[i]
        out = str(seg_dir / f"{i:02d}_{s['id']}.mp4")
        jobs.append((s, items[s["id"]], n, out))

    def run(j):
        s, it, n, out = j
        (render_photo if it["kind"] == "photo" else render_video)(s, it, n, out, beat_frames)
        return out
    t0 = time.time()
    with cf.ThreadPoolExecutor(14) as ex:
        outs = list(ex.map(run, jobs))
    log(f"segments rendered in {time.time() - t0:.1f}s")
    lst = seg_dir / "list.txt"
    lst.write_text("".join(f"file '{o}'\n" for o in outs))
    silent = work / f"silent_{tag}.mp4"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy",
                    str(silent)], check=True)
    total = cuts[-1] / FPS
    fade_st = max(0, total - 1.6)
    afilt = f"afade=t=in:d=0.05,afade=t=out:st={fade_st:.2f}:d=1.6"
    # two-pass loudnorm to -14 LUFS / -1 dBTP
    meas = subprocess.run(["ffmpeg", "-hide_banner", "-ss", f"{music['offset']:.3f}", "-t", f"{total:.3f}",
                           "-i", music_path, "-af", afilt + ",loudnorm=I=-14:TP=-1.0:LRA=11:print_format=json",
                           "-f", "null", "-"], capture_output=True, text=True).stderr
    m = json.loads(meas[meas.rfind("{"):meas.rfind("}") + 1])
    ln = (f"loudnorm=I=-14:TP=-1.0:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
          f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
    out = work / f"reel_{tag}.mp4"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(silent), "-ss", f"{music['offset']:.3f}", "-t",
                    f"{total:.3f}", "-i", music_path, "-map", "0:v", "-map", "1:a", "-c:v", "copy",
                    "-af", afilt + "," + ln + ",aresample=48000", "-c:a", "aac", "-b:a", "192k", "-shortest",
                    "-movflags", "+faststart", str(out)], check=True)
    chk = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(out), "-af", "loudnorm=print_format=json", "-f", "null",
                          "-"], capture_output=True, text=True).stderr
    mm = json.loads(chk[chk.rfind("{"):chk.rfind("}") + 1])
    edl = {"duration": round(total, 2), "fps": FPS, "size": f"{W}x{H}",
           "loudness": {"lufs": mm["input_i"], "true_peak": mm["input_tp"]},
           "music": {"bpm": round(music["bpm"], 1), "drop_at": music["drop"], "source": music["label"]},
           "captions": "none (user requested zero text overlays)",
           "shots": []}
    for i, s in enumerate(plan["shots"]):
        it = items[s["id"]]
        edl["shots"].append({"i": i, "id": s["id"], "kind": it["kind"], "t_in": round(cuts[i] / FPS, 2),
                             "t_out": round(cuts[i + 1] / FPS, 2), "beats": s["beats"], "src_in": s.get("in", 0),
                             "fx": s.get("fx", "none"), "zoom": s.get("zoom"), "focus": s["focus"],
                             "role": s.get("role"), "desc": it.get("desc", ""), "orientation":
                             "portrait" if it["height"] >= it["width"] else "landscape"})
    return out, edl


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--media", default="/opt/media/hackathon")
    ap.add_argument("--work", default="/opt/editor-eye/work")
    ap.add_argument("--music", default="/opt/editor-eye/music_eleven.mp3")
    ap.add_argument("--drop-hint", type=float, default=22.0)
    ap.add_argument("--target", type=float, default=30.0)
    ap.add_argument("--out", default="/srv/director/reels/best-hackathon")
    ap.add_argument("--rubric", default="/opt/editor-eye/EDIT-RUBRIC.md")
    ap.add_argument("--keys", default="/opt/memories-director/extra-keys.env")
    ap.add_argument("--iterations", type=int, default=3)
    ap.add_argument("--start-version", type=int, default=1)
    a = ap.parse_args()
    load_env(a.keys)
    work = Path(a.work); work.mkdir(parents=True, exist_ok=True)
    T0 = time.time(); timings = {}

    inv = cached(work / "inventory.json", lambda: ee.to_json(ee.inventory(a.media)))
    items_dc = [ee.Item(**i) for i in inv]
    log(f"inventory: {sum(i['kind'] == 'photo' for i in inv)} photos, {sum(i['kind'] == 'video' for i in inv)} videos")
    sheets = cached(work / "sheets.json", lambda: ee.to_json(ee.build_sheets(items_dc, work / "sheets")))
    sheets_dc = [ee.Sheet(**s) for s in sheets]
    timings["sheets"] = round(time.time() - T0, 1)

    rating = cached(work / "rating.json", lambda: ee.rate_and_tag(sheets_dc, items_dc, context=CONTEXT))
    timings["rating"] = round(time.time() - T0, 1)
    log(f"rated {len(rating.get('items', []))} items; missing {rating.get('missing')}")
    rmap = {r["id"]: r for r in rating["items"]}
    items = {i["id"]: {**i, "desc": rmap.get(i["id"], {}).get("desc", "")} for i in inv}

    music = cached(work / "music.json", lambda: analyse_music(a.music, a.drop_hint))
    log(f"music: {music['bpm']:.1f} BPM, drop at {music['drop']}s (abs {music['drop_abs']:.2f}), offset {music['offset']:.3f}")

    rubric = Path(a.rubric).read_text()
    history = json.loads((work / "history.json").read_text()) if (work / "history.json").exists() else []
    plan, crit = None, None
    if a.start_version > 1:
        plan = json.loads((work / f"plan_v{a.start_version - 1}.json").read_text())
        crit = json.loads((work / f"critique_v{a.start_version - 1}.json").read_text())
    for v in range(a.start_version, a.start_version + a.iterations):
        pf = work / f"plan_v{v}.json"
        if pf.exists():
            plan = json.loads(pf.read_text())
        else:
            plan = ee.plan_cut(rating, items_dc, music, sheets=sheets_dc, target_s=a.target, brief=BRIEF,
                               feedback=crit, previous=plan)
            pf.write_text(json.dumps(plan, indent=1, ensure_ascii=False))
        log(f"v{v}: {len(plan['shots'])} shots, {plan['total_beats']} beats")
        reel, edl = render(plan, items, music, a.music, work, f"v{v}")
        (work / f"edl_v{v}.json").write_text(json.dumps(edl, indent=1, ensure_ascii=False))
        fs = ee.make_frame_sheets(str(reel), work / f"frames_v{v}")
        timings[f"render_v{v}"] = round(time.time() - T0, 1)
        publish(a.out, reel, fs, edl, plan, f"v{v}")
        crit = ee.critique(fs, edl, rubric, notes=(
            "Captions: the owner explicitly asked for ZERO text overlays; score 'captions' 10 if no text is burned in "
            "(timestamps on the frame sheet tiles are review labels, not in the video).\nContent brief the editor had to "
            "follow (do NOT penalise the absence of stage/demo/booths/mascot; the arc is the build itself):\n" + BRIEF))
        (work / f"critique_v{v}.json").write_text(json.dumps(crit, indent=1, ensure_ascii=False))
        timings[f"critique_v{v}"] = round(time.time() - T0, 1)
        sc = crit.get("scores", {})
        history.append({"version": v, "scores": sc, "total": crit.get("total"), "verdict": crit.get("verdict"),
                        "shots": len(plan["shots"]), "unique": len({s['id'] for s in plan['shots']}),
                        "reel": str(reel), "frames": fs, "usage_usd": round(ee.cost_usd(), 3)})
        (work / "history.json").write_text(json.dumps(history, indent=1, ensure_ascii=False))
        log(f"v{v} critique: total {crit.get('total')} {sc} -- {crit.get('verdict')}")
        if sc and min(sc.values()) >= 8:
            break
    best = max(history, key=lambda h: (h["total"] or 0))
    publish(a.out, Path(best["reel"]), best["frames"], json.loads((work / f"edl_v{best['version']}.json").read_text()),
            json.loads((work / f"plan_v{best['version']}.json").read_text()), "final")
    summary = {"best_version": best["version"], "history": history, "timings_s": timings,
               "claude_usage": ee.USAGE, "claude_cost_usd_this_run": round(ee.cost_usd(), 3)}
    (work / "summary.json").write_text(json.dumps(summary, indent=1, ensure_ascii=False))
    print(json.dumps(summary, indent=1, ensure_ascii=False))


def publish(out_dir: str, reel: Path, frames: list[str], edl: dict, plan: dict, tag: str):
    out = Path(out_dir); out.mkdir(parents=True, exist_ok=True)
    name = "best-hackathon-reel.mp4" if tag == "final" else f"best-hackathon-reel-{tag}.mp4"
    shutil.copy(reel, out / name)
    for k, f in enumerate(frames, 1):
        shutil.copy(f, out / (f"frame-sheet-{k}.jpg" if tag == "final" else f"frame-sheet-{tag}-{k}.jpg"))
    # cover = middle of the peak (drop) shot
    peak = next((s for s in edl["shots"] if s.get("role") == "peak"), edl["shots"][len(edl["shots"]) // 2])
    t = (peak["t_in"] + peak["t_out"]) / 2
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-ss", f"{t:.2f}", "-i", str(reel), "-frames:v", "1", "-q:v", "2",
                    str(out / ("cover.jpg" if tag == "final" else f"cover-{tag}.jpg"))], check=True)
    (out / ("edl.json" if tag == "final" else f"edl-{tag}.json")).write_text(json.dumps({"edl": edl, "plan": plan}, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
