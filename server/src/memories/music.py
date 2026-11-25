"""Royalty-free music library (assets/music/tracks.json)."""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

from .config import get_settings


@lru_cache
def tracks() -> list[dict]:
    d = get_settings().assets_dir / "music"
    try:
        items = json.loads((d / "tracks.json").read_text())
    except Exception:
        return []
    out = []
    for t in items:
        p = d / t["file"]
        if p.exists():
            out.append({**t, "path": str(p), "bpm": t.get("bpm") or 100.0})
    return out


def pick_track(mood: str, avoid: set[str] | None = None) -> dict | None:
    ts = tracks()
    if not ts:
        return None
    avoid = avoid or set()
    mood = (mood or "").lower()
    ranked = sorted(ts, key=lambda t: (t["file"] in avoid, 0 if t.get("mood") == mood else 1 if mood in t.get("moods", []) else 2))
    return ranked[0]


def beat_interval(track: dict | None) -> float:
    bpm = float((track or {}).get("bpm") or 100.0)
    return 60.0 / bpm
