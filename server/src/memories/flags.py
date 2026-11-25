"""Flagsmith (server key) with safe defaults. Never raises; flags cached for 15 s."""
from __future__ import annotations

import json
import logging
import threading
import time
from typing import Any

from .config import get_settings

log = logging.getLogger("memories.flags")

DEFAULTS: dict[str, tuple[bool, Any]] = {
    "render_profile": (False, None),
    "peak_mode": (False, None),
    "ml_lite_mode": (False, None),
    "shot_coach": (True, {"max_cards": 3}),
    "director_strategy": (True, "single_shot"),
    "vision_model": (False, None),
    "elder_mode": (False, None),
}

_client = None
_client_lock = threading.Lock()
_cache: tuple[float, dict] | None = None


def _default_handler(name: str):
    from flagsmith.models import DefaultFlag
    enabled, value = DEFAULTS.get(name, (False, None))
    return DefaultFlag(enabled=enabled, value=value if not isinstance(value, dict) else json.dumps(value))


def client():
    global _client
    s = get_settings()
    if not s.flagsmith_server_key:
        return None
    with _client_lock:
        if _client is None:
            try:
                from flagsmith import Flagsmith
                from urllib3 import Retry
                kw: dict[str, Any] = dict(environment_key=s.flagsmith_server_key, default_flag_handler=_default_handler,
                                          request_timeout_seconds=2, enable_events=True,
                                          retries=Retry(total=1, backoff_factor=0.1))
                if s.flagsmith_api_url:
                    kw["api_url"] = s.flagsmith_api_url
                _client = Flagsmith(**kw)
            except Exception as e:
                log.warning("flagsmith init failed: %s", e)
                return None
    return _client


def _parse(v: Any) -> Any:
    if isinstance(v, str):
        t = v.strip()
        if t[:1] in "{[":
            try:
                return json.loads(t)
            except Exception:
                return v
    return v


def _read(flags_obj, name: str) -> dict:
    try:
        f = flags_obj.get_flag(name)
        return {"enabled": bool(f.enabled), "value": _parse(f.value), "default": bool(getattr(f, "is_default", False))}
    except Exception:
        en, val = DEFAULTS.get(name, (False, None))
        return {"enabled": en, "value": val, "default": True}


def env_flags(force: bool = False) -> dict[str, dict]:
    """Environment-level flags (cached 15 s)."""
    global _cache
    if not force and _cache and time.time() - _cache[0] < 15:
        return _cache[1]
    out: dict[str, dict] = {}
    c = client()
    flags_obj = None
    if c is not None:
        try:
            flags_obj = c.get_environment_flags()
        except Exception as e:
            log.warning("flagsmith unreachable: %s", e)
    for name in DEFAULTS:
        if flags_obj is not None:
            out[name] = _read(flags_obj, name)
        else:
            en, val = DEFAULTS[name]
            out[name] = {"enabled": en, "value": val, "default": True}
    _cache = (time.time(), out)
    return out


_id_cache: dict[str, tuple[float, dict]] = {}


def identity_flags(identifier: str, traits: dict | None = None) -> dict[str, dict]:
    hit = _id_cache.get(identifier)
    if hit and time.time() - hit[0] < 15 and not traits:
        return hit[1]
    c = client()
    base = dict(env_flags())
    if c is None or not identifier:
        return base
    try:
        fo = c.get_identity_flags(identifier=identifier, traits=traits or {})
        for name in DEFAULTS:
            base[name] = _read(fo, name)
    except Exception as e:
        log.warning("identity flags failed: %s", e)
    _id_cache[identifier] = (time.time(), base)
    return base


def director_strategy(member: str | None) -> tuple[str, dict]:
    """Experiment flag director_strategy (single_shot | agentic)."""
    c = client()
    if c is None or not member:
        return str(env_flags()["director_strategy"]["value"] or "single_shot"), {"source": "default"}
    try:
        f = c.get_experiment_flag("director_strategy", identifier=member)
        val = str(f.value or "single_shot")
        exp = getattr(f, "experiment", None)
        return (val if val in ("single_shot", "agentic") else "single_shot"), {
            "source": "experiment" if exp is not None else "flag", "variant": getattr(f, "variant", None),
            "in_experiment": bool(getattr(exp, "in_experiment", False)) if exp is not None else False}
    except Exception as e:
        log.warning("director_strategy experiment lookup failed: %s", e)
        try:
            fo = c.get_identity_flags(identifier=member)
            val = str(fo.get_feature_value("director_strategy") or "single_shot")
            return (val if val in ("single_shot", "agentic") else "single_shot"), {"source": "identity"}
        except Exception:
            return "single_shot", {"source": "default"}


def track(event: str, identifier: str | None, **metadata: Any) -> bool:
    c = client()
    if c is None:
        return False
    try:
        c.track_event(event, identifier=identifier, metadata=metadata or None)
        return True
    except Exception as e:
        log.warning("track_event failed: %s", e)
        return False


def close() -> None:
    if _client is not None:
        try:
            _client.close()
        except Exception:
            pass


def mode(flags: dict[str, dict] | None = None) -> str:
    f = flags or env_flags()
    parts = [n for n, key in (("peak", "peak_mode"), ("lite", "ml_lite_mode")) if f.get(key, {}).get("enabled")]
    return "+".join(parts) if parts else "normal"


def ml_lite(flags: dict[str, dict] | None = None) -> dict | None:
    f = (flags or env_flags()).get("ml_lite_mode", {})
    if not f.get("enabled"):
        return None
    v = f.get("value")
    return v if isinstance(v, dict) else {}


def render_overrides(flags: dict[str, dict] | None = None) -> dict:
    """render_profile JSON, then peak_mode JSON (peak wins) -> {preview:{...}, final:{...}, transitions?}"""
    f = flags or env_flags()
    out: dict = {}
    rp = f.get("render_profile", {})
    if rp.get("enabled") and isinstance(rp.get("value"), dict):
        out.update(rp["value"])
    pm = f.get("peak_mode", {})
    if pm.get("enabled"):
        v = pm.get("value") if isinstance(pm.get("value"), dict) else {"final": {"w": 720, "h": 1280, "fps": 24}}
        for k, val in v.items():
            if isinstance(val, dict) and isinstance(out.get(k), dict):
                out[k] = {**out[k], **val}
            else:
                out[k] = val
    return out
