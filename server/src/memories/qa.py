"""Edit-rubric validators (docs/EDIT-RUBRIC.md automatable checks). Pure functions, shared by the director,
the renderer and scripts/eval_reel.py."""
from __future__ import annotations

import re
from statistics import mean, pstdev
from typing import Any

SAFE_BOX = (60, 250, 950, 1540)  # x0, y0, x1, y1 at 1080x1920 (§8.6)
# per-destination length windows (default target, unless the prompt asks for a length)
LENGTHS = {
    "wa_status": (15.0, 20.0, 17.5),
    "insta_reel": (15.0, 25.0, 20.0),
    "insta_story": (10.0, 15.0, 13.0),
}
MIN_CAPTION_PX = 64
LOW_VALUE_RE = re.compile(r"walk|corridor|carpet|hallway|aisle|arriv|entrance|passing|queue|exploring|gathering|"
                          r"browsing|signage|banner|building|exterior|kiosk|reading display", re.I)


def clip_len(c: dict) -> float:
    return (c["out_s"] - c["in_s"]) if c.get("kind") == "video" else c.get("hold_s", 0.0)


def dhash_img(im) -> int:
    from PIL import Image
    g = im.convert("L").resize((9, 8), Image.BILINEAR)
    px = list(g.getdata())
    v = 0
    for y in range(8):
        for x in range(8):
            v = (v << 1) | (px[y * 9 + x] > px[y * 9 + x + 1])
    return v


def hamming(a: int, b: int) -> int:
    return bin(int(a) ^ int(b)).count("1")


def mean_luma(im) -> float:
    g = im.convert("L")
    px = list(g.getdata())
    return sum(px) / max(1, len(px))


def rect_inside(r: list[float] | tuple, box: tuple = SAFE_BOX) -> bool:
    return r[0] >= box[0] - 1 and r[1] >= box[1] - 1 and r[2] <= box[2] + 1 and r[3] <= box[3] + 1


def rect_overlap(a, b) -> float:
    """Intersection area / area of a."""
    ix = max(0.0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    area = max(1e-6, (a[2] - a[0]) * (a[3] - a[1]))
    return ix * iy / area


def length_window(destination: str, prompt: str = "") -> tuple[float, float, float]:
    """(min, max, target) seconds; an explicit '30 sec' / '25s' in the prompt overrides the default window."""
    lo, hi, tgt = LENGTHS.get(destination, LENGTHS["wa_status"])
    m = re.search(r"(\d{2})\s*(?:s\b|sec|second|seconds|सेकंड)", prompt or "", re.I)
    if m:
        want = float(m.group(1))
        cap = 15.0 if destination == "insta_story" else 30.0
        want = max(8.0, min(cap, want))
        return max(8.0, want - 2.5), want, want - 1.0
    return lo, hi, tgt


def is_low_value(meta: dict) -> bool:
    text = f"{meta.get('moment_tag') or ''} {meta.get('caption') or ''} {meta.get('scene') or ''}"
    return int(meta.get("people_count") or 0) == 0 and not meta.get("hero") or bool(LOW_VALUE_RE.search(text))


def evaluate(cut: dict, destination: str, info: dict, hashes: list[int], first_luma: float = 128.0,
             audio: dict | None = None, prompt: str = "") -> dict[str, Any]:
    clips = cut["clips"]
    durs = [clip_len(c) for c in clips]
    lo, hi, _ = length_window(destination, prompt)
    total = info.get("duration", sum(durs))
    checks: dict[str, Any] = {}
    fails: list[str] = []
    warns: list[str] = []
    checks["duration_s"] = round(total, 2)
    checks["duration_window"] = [lo, hi]
    if not (lo - 0.5 <= total <= hi + 0.5):
        warns.append(f"duration {total:.1f}s outside {lo:.0f}-{hi:.0f}s for {destination}")
    checks["aspect"] = f"{info.get('w')}x{info.get('h')}"
    if info.get("w") and abs(info["w"] / info["h"] - 9 / 16) > 0.01:
        fails.append("wrong aspect ratio")
    checks["shots"] = len(clips)
    checks["hold"] = {"mean": round(mean(durs), 2), "min": round(min(durs), 2), "max": round(max(durs), 2),
                      "std": round(pstdev(durs), 2)}
    if max(durs) > 4.0:
        warns.append(f"a shot holds {max(durs):.1f}s (> 4 s)")
    checks["first_cut_s"] = round(durs[0], 2)
    if durs[0] > 2.0:
        warns.append(f"first cut at {durs[0]:.1f}s (> 2 s)")
    if first_luma < 16:
        fails.append("black first frame")
    # duplicates / near duplicates (pHash at shot midpoints)
    near = []
    for i in range(len(hashes)):
        for j in range(i + 1, len(hashes)):
            d = hamming(hashes[i], hashes[j])
            if d <= 8:
                near.append((i, j, d))
    checks["near_duplicates"] = near
    if any(j == i + 1 for i, j, _ in near):
        fails.append("duplicate shot directly adjacent")
    elif near:
        warns.append(f"{len(near)} near-duplicate pair(s)")
    ids = [c["asset_id"] for c in clips]
    adj_same = sum(1 for a, b in zip(ids, ids[1:]) if a == b)
    checks["consecutive_same_source"] = adj_same
    vids = [c["asset_id"] for c in clips if c.get("kind") == "video"]
    checks["max_clips_per_video"] = max([vids.count(v) for v in vids] or [0])
    if checks["max_clips_per_video"] > 1:
        warns.append("a source video is used more than once")
    vid_s = sum(d for d, c in zip(durs, clips) if c.get("kind") == "video")
    checks["video_share"] = round(vid_s / max(0.01, sum(durs)), 2)
    long_vid = [round(d, 2) for d, c in zip(durs, clips) if c.get("kind") == "video" and d > 3.05]
    if long_vid:
        warns.append(f"video clips longer than 3 s: {long_vid}")
    # people / value
    metas = [c.get("meta") or {} for c in clips]
    low = [i for i, m in enumerate(metas) if m and is_low_value(m)]
    checks["low_value_shots"] = low
    if len(low) > max(1, len(clips) // 4):
        warns.append(f"{len(low)} low-value shots (no people / walking / corridor)")
    people_shots = sum(1 for m in metas if int(m.get("people_count") or 0) > 0)
    checks["people_share"] = round(people_shots / max(1, len(clips)), 2)
    last = metas[-1] if metas else {}
    checks["ending"] = {"people": last.get("people_count"), "group": last.get("is_group"), "hold_s": round(durs[-1], 2),
                        "moment": last.get("moment_tag")}
    if not last.get("is_group") or durs[-1] < 2.0:
        warns.append("ending is not a group shot held >= 2 s")
    checks["hook"] = {"people": metas[0].get("people_count") if metas else None, "moment": metas[0].get("moment_tag") if metas else None}
    # captions
    caps = cut.get("captions")
    if caps is None:
        caps = [{"text": c.get("caption"), "font_px": None, "bbox": None} for c in clips if c.get("caption")]
    checks["captions"] = len(caps)
    if not 3 <= len(caps) <= 5:
        warns.append(f"{len(caps)} captions (want 3-5)")
    small = [c["text"] for c in caps if c.get("font_px") is not None and c["font_px"] < MIN_CAPTION_PX]
    unknown = [c["text"] for c in caps if c.get("font_px") is None]
    if small:
        warns.append(f"captions under {MIN_CAPTION_PX}px: {small}")
    if unknown:
        warns.append("caption size/position not recorded (legacy renderer)")
    outside = [c["text"] for c in caps if c.get("bbox") and not rect_inside(c["bbox"])]
    if outside:
        warns.append(f"captions outside safe area: {outside}")
    over_face = [c["text"] for c in caps if c.get("bbox") and any(rect_overlap(f, c["bbox"]) > 0.02 or rect_overlap(c["bbox"], f) > 0.02
                                                                   for f in c.get("faces") or [])]
    if over_face:
        (fails if caps and over_face and over_face[0] == caps[0]["text"] else warns).append(f"captions over faces: {over_face}")
    long_caps = [c["text"] for c in caps if c.get("text") and len(str(c["text"]).split()) > 5]
    if long_caps:
        warns.append(f"captions over 5 words: {long_caps}")
    # transitions
    checks["crossfades"] = cut.get("crossfades", None)
    if audio:
        checks["audio"] = audio
        if audio.get("max_db", -99) >= -0.1:
            fails.append("audio clipping")
    return {"checks": checks, "hard_fails": fails, "warnings": warns,
            "auto_score": max(0, 10 - 2 * len(fails) - len(warns))}
