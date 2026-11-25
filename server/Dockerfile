FROM python:3.12-slim-trixie
ENV PYTHONUNBUFFERED=1 UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_CONCURRENT_DOWNLOADS=2 UV_HTTP_TIMEOUT=180
# ffmpeg + libraqm (Pillow RAQM layout for Devanagari) + Noto fonts
RUN apt-get update && apt-get install -y --no-install-recommends \
      ffmpeg libraqm0 libfribidi0 libharfbuzz0b fonts-noto-core curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:0.9.7 /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock README.md ./
# Linux Pillow wheels bundle libraqm (fribidi loaded at runtime), so drop the macOS-only source-build setting
RUN sed -i '/^\[tool.uv\]/,$d' pyproject.toml && uv sync --no-dev --no-install-project
COPY src ./src
COPY assets ./assets
RUN uv sync --no-dev
ENV DATA_DIR=/data PATH="/app/.venv/bin:$PATH"
VOLUME /data
EXPOSE 8000
HEALTHCHECK CMD curl -fsS http://127.0.0.1:8000/health || exit 1
CMD ["uvicorn", "memories.api:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
