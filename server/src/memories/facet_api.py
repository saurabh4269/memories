"""Facet quality signals over HTTP (router auto-loaded by api.py when present).

GET  /v1/albums/{album_id}/facet          -> summary + per-asset scores (from the local cache)
POST /v1/albums/{album_id}/facet/refresh  -> rebuild the cache from facet_raw.json + Immich
"""
from __future__ import annotations

import asyncio

from fastapi import APIRouter, HTTPException, Query

from memories import facet_scores

router = APIRouter(tags=["facet"])


@router.get("/v1/albums/{album_id}/facet")
async def get_facet(album_id: str, summary_only: bool = Query(False)) -> dict:
    doc = await asyncio.to_thread(facet_scores.load_doc, album_id)
    if not doc:
        raise HTTPException(404, "no Facet scores for this album (run the Facet export, then POST .../facet/refresh)")
    if summary_only:
        return {k: v for k, v in doc.items() if k != "scores"}
    return doc


@router.post("/v1/albums/{album_id}/facet/refresh")
async def refresh_facet(album_id: str) -> dict:
    if not facet_scores.raw_path().exists():
        raise HTTPException(409, f"Facet export not found at {facet_scores.raw_path()}")
    try:
        doc = await asyncio.to_thread(facet_scores.refresh_scores, album_id)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"Facet refresh failed: {e}") from e
    return {k: v for k, v in doc.items() if k != "scores"}
