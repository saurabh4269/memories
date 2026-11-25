"""Settings via environment variables (pydantic-settings). Never log secret values."""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

SERVER_DIR = Path(__file__).resolve().parents[2]
REPO_DIR = SERVER_DIR.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        # later files override earlier ones; real env vars override all
        env_file=(
            str(REPO_DIR / "knowledge-dump/festive-hacks-context/.env"),
            str(REPO_DIR / "knowledge-dump/azure/immich.env"),
            str(SERVER_DIR / ".env"),
        ),
        extra="ignore",
    )

    sarvam_api_key: str = ""
    sarvam_base_url: str = "https://api.sarvam.ai"
    vision_model: str = "gemma4"
    director_model: str = "sarvam-105b"

    flagsmith_server_key: str = ""
    flagsmith_api_url: str | None = None

    immich_url: str = Field("", validation_alias=AliasChoices("IMMICH_URL", "IMMICH_SERVER_URL", "IMMICH_BASE_URL"))
    immich_api_key: str = Field("", validation_alias=AliasChoices("IMMICH_API_KEY", "IMMICH_KEY"))
    immich_verify_tls: bool = True
    # video source for analysis/render: "original" (HTTP range seeking) or "playback" (720p transcode)
    video_source: str = "original"
    # when running next to Immich: map Immich originalPath prefix -> local path to read files directly
    immich_path_from: str = ""
    immich_path_to: str = ""

    data_dir: Path = SERVER_DIR / "data"
    assets_dir: Path = SERVER_DIR / "assets"
    public_base_url: str = "http://localhost:8000"

    video_encoder: str = "auto"  # auto | libx264 | h264_videotoolbox
    render_workers: int = 0  # 0 = CPU count
    analysis_concurrency: int = 4
    analysis_batch: int = 6
    poll_interval_s: int = 10  # >0 enables background analysis poller (watched albums)

    @property
    def immich_api(self) -> str:
        u = self.immich_url.rstrip("/")
        return u if u.endswith("/api") else u + "/api"


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    s.data_dir.mkdir(parents=True, exist_ok=True)
    return s
