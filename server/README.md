# Memories director service

FastAPI service that turns a shared Immich event album into two post-ready vertical reels from a vague prompt.

Run locally: `uv sync && uv run uvicorn memories.api:app --port 8000` (env: see `.env.example`; on macOS Pillow is built
from source so it links libraqm: `brew install libraqm fribidi` and export CFLAGS/LDFLAGS for /opt/homebrew).

CLI: `uv run python -m memories.demo --album <id> --prompt "WA status ke liye family wali, thoda emotional" --dest wa_status --final -v`

Tests: `uv run pytest -q`. Docker: `docker build -t memories-director . && docker run --network host --env-file .env -v /srv/director:/data memories-director`.

Modules: `sarvam.py` (client, rate limits, gemma4 vision, sarvam-105b plan, saaras, mayura, bulbul), `analysis.py`
(album analysis, video contact sheets, cache in sqlite + Immich metadata key `memories`, poller), `director.py` (EDL
prompt + validation + fallback), `agentic.py` (tool-calling director), `render.py` (ffmpeg segments + xfade join),
`captions.py` (Pillow RAQM PNG captions), `coach.py` (missing-shot cards), `flags.py` (Flagsmith), `pipeline.py`, `api.py`.

Music: `assets/music/tracks.json` (Kevin MacLeod, CC BY 4.0, attribution recorded per track).
