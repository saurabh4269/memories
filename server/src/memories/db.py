"""Tiny sqlite store: analysis cache, watched albums, reels, shot lists, event context."""
from __future__ import annotations

import json
import sqlite3
import threading
import time
from typing import Any

from .config import get_settings

_lock = threading.Lock()
_conn: sqlite3.Connection | None = None


def conn() -> sqlite3.Connection:
    global _conn
    if _conn is None:
        path = get_settings().data_dir / "memories.sqlite"
        _conn = sqlite3.connect(path, check_same_thread=False)
        _conn.execute("PRAGMA journal_mode=WAL")
        _conn.executescript("""
        CREATE TABLE IF NOT EXISTS analysis (asset_id TEXT PRIMARY KEY, album_id TEXT, data TEXT, updated REAL);
        CREATE TABLE IF NOT EXISTS albums (album_id TEXT PRIMARY KEY, added REAL);
        CREATE TABLE IF NOT EXISTS kv (ns TEXT, key TEXT, data TEXT, updated REAL, PRIMARY KEY (ns, key));
        """)
    return _conn


def get_analysis(asset_ids: list[str]) -> dict[str, dict]:
    if not asset_ids:
        return {}
    out: dict[str, dict] = {}
    with _lock:
        c = conn()
        for i in range(0, len(asset_ids), 500):
            chunk = asset_ids[i : i + 500]
            q = f"SELECT asset_id, data FROM analysis WHERE asset_id IN ({','.join('?' * len(chunk))})"
            for aid, data in c.execute(q, chunk):
                out[aid] = json.loads(data)
    return out


def put_analysis(asset_id: str, album_id: str, data: dict) -> None:
    with _lock:
        conn().execute("INSERT OR REPLACE INTO analysis VALUES (?,?,?,?)",
                       (asset_id, album_id, json.dumps(data, ensure_ascii=False), time.time()))
        conn().commit()


def watch_album(album_id: str) -> None:
    with _lock:
        conn().execute("INSERT OR IGNORE INTO albums VALUES (?,?)", (album_id, time.time()))
        conn().commit()


def watched_albums() -> list[str]:
    with _lock:
        return [r[0] for r in conn().execute("SELECT album_id FROM albums")]


def kv_get(ns: str, key: str) -> Any:
    with _lock:
        r = conn().execute("SELECT data FROM kv WHERE ns=? AND key=?", (ns, key)).fetchone()
    return json.loads(r[0]) if r else None


def kv_put(ns: str, key: str, data: Any) -> None:
    with _lock:
        conn().execute("INSERT OR REPLACE INTO kv VALUES (?,?,?,?)",
                       (ns, key, json.dumps(data, ensure_ascii=False, default=str), time.time()))
        conn().commit()
