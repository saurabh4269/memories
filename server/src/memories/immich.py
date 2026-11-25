"""Minimal async Immich v3 client (x-api-key)."""
from __future__ import annotations

import logging
import re
from datetime import datetime, timezone
from typing import Any

import httpx

from .config import get_settings

log = logging.getLogger("memories.immich")


def parse_duration(d: Any) -> float:
    """Immich durations look like '0:00:05.123000'. Returns seconds (0 for images/unknown)."""
    if d is None:
        return 0.0
    if isinstance(d, (int, float)):
        return float(d) / 1000.0  # Immich v3: integer milliseconds
    m = re.match(r"^(\d+):(\d+):(\d+(?:\.\d+)?)$", str(d).strip())
    if not m:
        try:
            return float(d)
        except Exception:
            return 0.0
    h, mi, s = m.groups()
    return int(h) * 3600 + int(mi) * 60 + float(s)


class ImmichClient:
    def __init__(self, base_url: str | None = None, api_key: str | None = None):
        s = get_settings()
        self.api = (base_url.rstrip("/") + "/api") if base_url else s.immich_api
        self.api_key = api_key if api_key is not None else s.immich_api_key
        self.http = httpx.AsyncClient(
            timeout=httpx.Timeout(60, connect=15), headers={"x-api-key": self.api_key},
            verify=s.immich_verify_tls, follow_redirects=True,
            transport=httpx.AsyncHTTPTransport(retries=3, verify=s.immich_verify_tls,
                                               limits=httpx.Limits(max_connections=16, max_keepalive_connections=16)),
        )
        self._search_form: str | None = None  # "albumIds" | "filter"

    @property
    def configured(self) -> bool:
        return bool(self.api_key and self.api.startswith("http"))

    async def aclose(self) -> None:
        await self.http.aclose()

    async def _json(self, method: str, path: str, **kw) -> Any:
        r = await self.http.request(method, self.api + path, **kw)
        if r.status_code >= 400:
            raise httpx.HTTPStatusError(f"Immich {method} {path} -> {r.status_code}: {r.text[:300]}",
                                        request=r.request, response=r)
        return r.json() if r.content else None

    # ---- albums / assets ----
    async def ping(self) -> Any:
        return await self._json("GET", "/server/ping")

    async def get_album(self, album_id: str, without_assets: bool = True) -> dict:
        return await self._json("GET", f"/albums/{album_id}", params={"withoutAssets": str(without_assets).lower()})

    async def list_albums(self) -> list[dict]:
        return await self._json("GET", "/albums")

    async def create_album(self, name: str, asset_ids: list[str] | None = None, description: str = "") -> dict:
        return await self._json("POST", "/albums", json={"albumName": name, "assetIds": asset_ids or [], "description": description})

    async def add_to_album(self, album_id: str, asset_ids: list[str]) -> Any:
        return await self._json("PUT", f"/albums/{album_id}/assets", json={"ids": asset_ids})

    async def _search(self, path: str, base: dict, album_id: str) -> dict:
        forms = [self._search_form] if self._search_form else ["albumIds", "filter"]
        last: Exception | None = None
        for form in forms:
            body = dict(base)
            if form == "albumIds":
                body["albumIds"] = [album_id]
            else:
                body["filter"] = {"albumIds": {"any": [album_id]}}
            try:
                res = await self._json("POST", path, json=body)
                self._search_form = form
                return res
            except httpx.HTTPStatusError as e:
                last = e
                if e.response.status_code != 400:
                    raise
        raise last  # type: ignore[misc]

    async def album_assets(self, album_id: str) -> list[dict]:
        out: list[dict] = []
        page: Any = 1
        while page:
            res = await self._search("/search/metadata", {"withPeople": True, "withExif": True, "size": 1000, "page": int(page)}, album_id)
            assets = res.get("assets", {})
            out.extend(assets.get("items", []))
            page = assets.get("nextPage")
            if len(out) > 5000:
                break
        if not out:
            # fallback: album endpoint with assets
            alb = await self.get_album(album_id, without_assets=False)
            out = alb.get("assets", [])
        return out

    async def smart_search(self, query: str, album_id: str, size: int = 10) -> list[dict]:
        res = await self._search("/search/smart", {"query": query, "size": size}, album_id)
        return res.get("assets", {}).get("items", [])

    async def people(self) -> list[dict]:
        res = await self._json("GET", "/people", params={"withHidden": "false", "size": 500})
        return res.get("people", []) if isinstance(res, dict) else res

    async def faces(self, asset_id: str) -> list[dict]:
        try:
            return await self._json("GET", "/faces", params={"id": asset_id})
        except Exception as e:  # faces are optional
            log.debug("faces failed for %s: %s", asset_id, e)
            return []

    # ---- media ----
    async def preview(self, asset_id: str, size: str = "preview") -> bytes:
        import asyncio
        for attempt in range(4):
            try:
                r = await self.http.get(f"{self.api}/assets/{asset_id}/thumbnail", params={"size": size})
                r.raise_for_status()
                return r.content
            except (httpx.TransportError, httpx.HTTPStatusError) as e:
                if attempt == 3 or (isinstance(e, httpx.HTTPStatusError) and e.response.status_code < 500 and e.response.status_code != 404):
                    raise
                await asyncio.sleep(1 + attempt)  # 404 = thumbnail not generated yet
        raise RuntimeError("unreachable")

    def playback_url(self, asset_id: str) -> str:
        return f"{self.api}/assets/{asset_id}/video/playback"

    def original_url(self, asset_id: str) -> str:
        return f"{self.api}/assets/{asset_id}/original"

    # ---- metadata ----
    async def get_metadata(self, asset_id: str, key: str = "memories") -> Any:
        r = await self.http.get(f"{self.api}/assets/{asset_id}/metadata/{key}")
        if r.status_code == 404 or r.status_code == 400:
            return None
        r.raise_for_status()
        j = r.json()
        return j.get("value") if isinstance(j, dict) else None

    async def put_metadata(self, asset_id: str, value: dict, key: str = "memories") -> Any:
        return await self._json("PUT", f"/assets/{asset_id}/metadata", json={"items": [{"key": key, "value": value}]})

    # ---- upload ----
    async def upload(self, path: str, created: datetime | None = None, filename: str | None = None) -> dict:
        import os
        created = created or datetime.fromtimestamp(os.path.getmtime(path), tz=timezone.utc)
        ts = created.isoformat()
        with open(path, "rb") as f:
            files = {"assetData": (filename or os.path.basename(path), f.read())}
        data = {"deviceAssetId": f"memories-{os.path.basename(path)}", "deviceId": "memories-director",
                "fileCreatedAt": ts, "fileModifiedAt": ts}
        return await self._json("POST", "/assets", files=files, data=data, timeout=300)
