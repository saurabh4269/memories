"""Per-request trace of stage timings and external calls (contextvar based)."""
from __future__ import annotations

import contextvars
import logging
import time
from contextlib import contextmanager
from typing import Any

log = logging.getLogger("memories")

_trace: contextvars.ContextVar[dict | None] = contextvars.ContextVar("memories_trace", default=None)


def new_trace() -> dict:
    t: dict[str, Any] = {"stages": {}, "calls": [], "events": []}
    _trace.set(t)
    return t


def current() -> dict | None:
    return _trace.get()


def record_call(kind: str, model: str, ms: float, ok: bool, **extra: Any) -> None:
    t = _trace.get()
    entry = {"kind": kind, "model": model, "ms": round(ms), "ok": ok, **extra}
    log.info("call %s", entry)
    if t is not None:
        t["calls"].append(entry)


def event(msg: str, **extra: Any) -> None:
    t = _trace.get()
    log.info("event %s %s", msg, extra or "")
    if t is not None:
        t["events"].append({"msg": msg, **extra})


@contextmanager
def stage(name: str):
    t0 = time.perf_counter()
    try:
        yield
    finally:
        ms = round((time.perf_counter() - t0) * 1000)
        log.info("stage %s %d ms", name, ms)
        t = _trace.get()
        if t is not None:
            t["stages"][name] = t["stages"].get(name, 0) + ms
