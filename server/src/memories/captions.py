"""Caption rendering to transparent PNG with Pillow (RAQM layout for Devanagari shaping)."""
from __future__ import annotations

import hashlib
import logging
import re
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, features

from .config import get_settings

log = logging.getLogger("memories.captions")

HAS_RAQM = features.check_feature("raqm")
if not HAS_RAQM:
    log.warning("Pillow RAQM layout not available: Devanagari will not shape correctly")

DEVANAGARI = re.compile(r"[ऀ-ॿ]")


@lru_cache(maxsize=16)
def _font(size: int, devanagari: bool) -> ImageFont.FreeTypeFont:
    d = get_settings().assets_dir / "fonts"
    name = "NotoSansDevanagari-Bold.ttf" if devanagari else "NotoSans-Bold.ttf"
    engine = ImageFont.Layout.RAQM if HAS_RAQM else ImageFont.Layout.BASIC
    return ImageFont.truetype(str(d / name), size, layout_engine=engine)


def _wrap(draw: ImageDraw.ImageDraw, text: str, font, max_w: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.textlength(trial, font=font) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines[:3]


SAFE = (60, 250, 950, 1540)  # caption box at 1080x1920 (EDIT-GRAMMAR §8.6)
BANDS = {"top": 430, "middle": 900, "bottom": 1390}  # block centre y at 1080x1920


def choose_position(role: str, faces: list[tuple[float, float, float, float]] | None) -> str:
    """Title prefers the upper third, labels the lower-middle; move to the other half if a face is there.
    faces: normalised (x0, y0, x1, y1) boxes in output-frame coordinates."""
    order = ["top", "bottom", "middle"] if role == "title" else ["bottom", "top", "middle"]
    for pos in order:
        cy = BANDS[pos] / 1920
        band = (cy - 0.07, cy + 0.07)
        if not any(f[1] < band[1] and f[3] > band[0] for f in faces or []):
            return pos
    return order[0]


def render_caption(text: str, width: int, height: int, out_dir: Path, role: str = "label",
                   position: str = "bottom") -> tuple[Path | None, dict]:
    """Full-frame transparent PNG: white bold text with a dark stroke + soft shadow, inside the safe box.
    Returns (path, meta) where meta has font_px and bbox in 1080x1920 coordinates."""
    text = (text or "").strip()
    if not text:
        return None, {}
    k = width / 1080
    dev = bool(DEVANAGARI.search(text))
    px = 100 if role == "title" else 70
    x0, y0s, x1, y1s = (v * k for v in SAFE)
    max_w = int((x1 - x0) - 30 * k)
    meas = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    while True:
        size = int(px * k)
        font = _font(size, dev)
        lines = _wrap(meas, text, font, max_w)
        if (len(lines) <= 2 and max(meas.textlength(l, font=font) for l in lines) <= max_w) or px <= 64:
            break
        px -= 6
    lines = lines[:2]
    line_h = int(size * (1.45 if dev else 1.22))
    block_h = line_h * len(lines)
    cy = BANDS.get(position, BANDS["bottom"]) * k
    top = int(min(max(cy - block_h / 2, y0s + 6 * k), y1s - block_h - 6 * k))
    key = hashlib.sha1(f"{text}|{width}x{height}|{role}|{position}|{HAS_RAQM}|v2".encode()).hexdigest()[:16]
    out = out_dir / f"cap_{key}.png"
    widths = [meas.textlength(l, font=font) for l in lines]
    cx = (x0 + x1) / 2
    bbox = [min(cx - w / 2 for w in widths), top, max(cx + w / 2 for w in widths), top + block_h]
    meta = {"text": text, "role": role, "position": position, "font_px": round(size / k),
            "bbox": [round(v / k) for v in bbox]}
    if out.exists():
        return out, meta
    out_dir.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    stroke = max(2, round(size * 0.075))
    for i, line in enumerate(lines):
        x = cx - widths[i] / 2
        sd.text((x + 3 * k, top + i * line_h + 4 * k), line, font=font, fill=(0, 0, 0, 160),
                stroke_width=stroke, stroke_fill=(0, 0, 0, 160))
    from PIL import ImageFilter
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(max(2, size // 12))))
    draw = ImageDraw.Draw(img)
    for i, line in enumerate(lines):
        x = cx - widths[i] / 2
        draw.text((x, top + i * line_h), line, font=font, fill=(255, 255, 255, 255),
                  stroke_width=stroke, stroke_fill=(10, 10, 10, 235))
    img.save(out)
    return out, meta


def caption_png(text: str, width: int, height: int, out_dir: Path, role: str = "label",
                position: str = "bottom") -> Path | None:
    return render_caption(text, width, height, out_dir, role, position)[0]
