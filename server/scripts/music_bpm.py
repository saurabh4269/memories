"""Estimate BPM + first-beat offset for assets/music/*.mp3 (numpy spectral-flux + autocorrelation).
Usage: uv run python scripts/music_bpm.py  -> updates bpm/beat_offset in assets/music/tracks.json"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

SR = 11025
HOP = 256


def onset_env(path: Path, seconds: int = 60) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-t", str(seconds), "-i", str(path), "-ac", "1", "-ar", str(SR),
                          "-f", "f32le", "-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32)
    n = 1024
    frames = np.lib.stride_tricks.sliding_window_view(x, n)[::HOP] * np.hanning(n)
    mag = np.log1p(np.abs(np.fft.rfft(frames, axis=1)))
    flux = np.maximum(0, np.diff(mag, axis=0)).sum(axis=1)
    flux = flux - np.convolve(flux, np.ones(16) / 16, mode="same")
    return np.maximum(flux, 0)


def tempo(env: np.ndarray) -> tuple[float, float]:
    fps = SR / HOP
    ac = np.correlate(env, env, mode="full")[len(env) - 1:]
    lags = np.arange(len(ac))
    bpm = 60 * fps / np.maximum(lags, 1)
    mask = (bpm >= 70) & (bpm <= 160)
    # weight towards ~110 bpm
    w = np.exp(-0.5 * (np.log2(bpm / 110) / 0.6) ** 2)
    lag = lags[mask][np.argmax((ac * w)[mask])]
    period = lag
    phases = [env[p::period].sum() for p in range(period)]
    offset = int(np.argmax(phases)) / fps
    return round(60 * fps / lag, 1), round(offset, 3)


if __name__ == "__main__":
    d = Path(__file__).resolve().parents[1] / "assets/music"
    tracks = json.loads((d / "tracks.json").read_text())
    for t in tracks:
        bpm, off = tempo(onset_env(d / t["file"]))
        t["bpm"], t["beat_offset"] = bpm, off
        print(t["file"], bpm, off, file=sys.stderr)
    (d / "tracks.json").write_text(json.dumps(tracks, indent=2, ensure_ascii=False) + "\n")
