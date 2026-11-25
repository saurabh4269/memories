"""Shared helpers for the Sarvam extras (invite / dictate / voiceover).

Kept separate so invite.py, dictate.py and voiceover.py don't import each other or the API layer.
"""
from __future__ import annotations

import hashlib
import json
import logging
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from .config import get_settings
from .sarvam import SarvamClient, SarvamError, parse_json_tolerant

log = logging.getLogger("memories.extras")


class ExtrasInputError(ValueError):
    """Bad caller input. `status` is the HTTP status the API layer should return."""

    def __init__(self, msg: str, status: int = 400):
        super().__init__(msg)
        self.status = status


class Timings:
    """Named wall-clock spans in ms; a repeated name accumulates."""

    def __init__(self) -> None:
        self.ms: dict[str, int] = {}
        self._t0 = time.perf_counter()

    @contextmanager
    def span(self, name: str):
        t0 = time.perf_counter()
        try:
            yield
        finally:
            self.ms[name] = self.ms.get(name, 0) + round((time.perf_counter() - t0) * 1000)

    def put(self, name: str, ms: float) -> None:
        self.ms[name] = round(ms)

    def total(self) -> dict[str, int]:
        return {**self.ms, "total": round((time.perf_counter() - self._t0) * 1000)}


def sha(data: bytes | str, n: int = 24) -> str:
    if isinstance(data, str):
        data = data.encode()
    return hashlib.sha256(data).hexdigest()[:n]


def extras_dir(*parts: str) -> Path:
    p = get_settings().data_dir.joinpath("extras", *parts)
    p.mkdir(parents=True, exist_ok=True)
    return p


def cache_get(ns: str, key: str) -> Any:
    p = extras_dir("cache", ns) / f"{key}.json"
    try:
        return json.loads(p.read_text())
    except FileNotFoundError:
        return None
    except Exception as e:  # corrupt cache entry: ignore and recompute
        log.warning("extras cache %s/%s unreadable: %s", ns, key, e)
        return None


def cache_put(ns: str, key: str, data: Any) -> None:
    p = extras_dir("cache", ns) / f"{key}.json"
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False))
    tmp.replace(p)


async def chat_json(client: SarvamClient, system: str, user: str, schema: dict, name: str, *,
                    model: str | None = None, reasoning_effort: str | None = "low",
                    max_tokens: int = 4000, temperature: float = 0.3) -> Any:
    """sarvam-105b JSON call: strict json_schema first, json_object on a 400, one retry if the
    reply is empty/unparseable (reasoning can eat the budget -> retry with reasoning off)."""
    model = model or get_settings().director_model
    msgs = [{"role": "system", "content": system}, {"role": "user", "content": user}]
    attempts: list[tuple[dict, str | None]] = [
        ({"type": "json_schema", "json_schema": {"name": name, "strict": True, "schema": schema}}, reasoning_effort),
        ({"type": "json_object"}, reasoning_effort),
        ({"type": "json_object"}, None),
    ]
    last: Exception | None = None
    for i, (fmt, effort) in enumerate(attempts):
        params: dict[str, Any] = {"temperature": temperature, "max_tokens": max_tokens, "response_format": fmt,
                                  "reasoning_effort": effort}
        try:
            resp = await client.chat(model, msgs, kind=f"llm_{name}", **params)
        except SarvamError as e:
            if str(e).startswith("400") and i < len(attempts) - 1:
                log.warning("%s: format %s rejected (%s), downgrading", name, fmt["type"], str(e)[:120])
                last = e
                continue
            raise
        try:
            return parse_json_tolerant(client.content_of(resp))
        except ValueError as e:
            fr = ((resp.get("choices") or [{}])[0]).get("finish_reason")
            log.warning("%s: unparseable reply (finish_reason=%s), retrying", name, fr)
            last = e
            continue
    raise SarvamError(f"{name}: no valid JSON from {model}: {last}")


def as_str(v: Any, limit: int = 200) -> str:
    if v is None:
        return ""
    return str(v).strip()[:limit]


def as_str_list(v: Any, limit: int = 30, item_limit: int = 120) -> list[str]:
    if v is None:
        return []
    if isinstance(v, str):
        v = [p for p in (x.strip() for x in v.replace(";", ",").split(",")) if p]
    if not isinstance(v, list):
        v = [v]
    out: list[str] = []
    seen: set[str] = set()
    for x in v:
        if isinstance(x, dict):
            x = x.get("name") or x.get("value") or ""
        s = as_str(x, item_limit)
        if s and s.lower() not in {"null", "none", "n/a"} and s.lower() not in seen:
            seen.add(s.lower())
            out.append(s)
        if len(out) >= limit:
            break
    return out
