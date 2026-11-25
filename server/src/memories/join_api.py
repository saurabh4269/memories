"""Event join: short-lived invite codes, a QR page, and Immich album redeem.

Mounted by api.py when this module imports (`router = APIRouter()`).
Invite codes and redemptions live in the shared SQLite file (tables created here).
"""
from __future__ import annotations

import logging
import re
import secrets
import sqlite3
import string
import time
from datetime import datetime, timezone
from html import escape
from io import BytesIO
from urllib.parse import quote

import httpx
import qrcode
from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse, Response
from pydantic import BaseModel

from . import db
from .config import get_settings

log = logging.getLogger("memories.join_api")

router = APIRouter(tags=["join"])

# Public origins from the API contract. Caddy serves Immich at the host root and
# the director under /director. The process itself talks to Immich on loopback.
PUBLIC_IMMICH = "https://memories-3870f5.centralindia.cloudapp.azure.com"
PUBLIC_DIRECTOR = PUBLIC_IMMICH + "/director"
EXPIRY_S = 7 * 24 * 3600
_CODE_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"
_PW_ALPHABET = string.ascii_letters + string.digits

_schema_ready = False


class ImmichJoinError(Exception):
    def __init__(self, status: int, detail: str):
        super().__init__(detail)
        self.status = status
        self.detail = detail


class InviteBody(BaseModel):
    created_by: str | None = None


class RedeemBody(BaseModel):
    code: str
    name: str
    language: str = ""
    role: str = "guest"


class ImmichJoinGateway:
    """Admin calls: create a user, then share the album as editor.

    `client` is injected in tests (httpx.MockTransport). Production opens a short-lived client.
    """

    def __init__(self, client: httpx.AsyncClient | None = None, api: str | None = None, api_key: str | None = None):
        s = get_settings()
        self._client = client
        self.api = (api if api is not None else s.immich_api).rstrip("/")
        self.api_key = s.immich_api_key if api_key is None else api_key
        self.verify = s.immich_verify_tls

    async def _request(self, method: str, path: str, body: dict) -> dict:
        headers = {"x-api-key": self.api_key, "Accept": "application/json"}
        url = self.api + path
        if self._client is not None:
            response = await self._client.request(method, url, json=body, headers=headers)
        else:
            async with httpx.AsyncClient(timeout=httpx.Timeout(30, connect=15), verify=self.verify, headers=headers) as client:
                response = await client.request(method, url, json=body)
        if response.status_code >= 400:
            # Response text can echo the submitted password; keep it out of errors and logs.
            raise ImmichJoinError(response.status_code, f"Immich {method} {path} failed ({response.status_code})")
        if not response.content:
            return {}
        data = response.json()
        return data if isinstance(data, dict) else {}

    async def create_user(self, *, email: str, password: str, name: str) -> str:
        data = await self._request("POST", "/admin/users", {
            "email": email,
            "password": password,
            "name": name,
            "notify": False,
            "shouldChangePassword": False,
        })
        user_id = data.get("id")
        if not user_id:
            raise ImmichJoinError(502, "Immich create user returned no id")
        return str(user_id)

    async def add_editor(self, album_id: str, user_id: str) -> None:
        await self._request("PUT", f"/albums/{album_id}/users", {
            "albumUsers": [{"userId": user_id, "role": "editor"}],
        })


def get_immich() -> ImmichJoinGateway:
    return ImmichJoinGateway()


def immich_public_url() -> str:
    """URL a phone can reach. Loopback settings stay for server-side admin calls."""
    url = (get_settings().immich_url or "").strip().rstrip("/")
    if url.endswith("/api"):
        url = url[: -len("/api")]
    lowered = url.lower()
    if not url or any(host in lowered for host in ("127.0.0.1", "localhost", "0.0.0.0")):
        return PUBLIC_IMMICH
    return url


def _iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _ensure_schema() -> None:
    global _schema_ready
    if _schema_ready:
        return
    with db._lock:
        conn = db.conn()
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS join_codes (
            code TEXT PRIMARY KEY,
            album_id TEXT NOT NULL,
            created_by TEXT,
            created_at REAL NOT NULL,
            expires_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS join_redemptions (
            code TEXT NOT NULL,
            name_key TEXT NOT NULL,
            name TEXT NOT NULL,
            language TEXT,
            role TEXT,
            email TEXT NOT NULL,
            password TEXT NOT NULL,
            member_id TEXT NOT NULL,
            album_id TEXT NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (code, name_key)
        );
        """)
        conn.commit()
        _schema_ready = True


def _new_code() -> str:
    return "".join(secrets.choice(_CODE_ALPHABET) for _ in range(8))


def _new_password() -> str:
    while True:
        password = "".join(secrets.choice(_PW_ALPHABET) for _ in range(16))
        if any(c.islower() for c in password) and any(c.isupper() for c in password) and any(c.isdigit() for c in password):
            return password


def _slug(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.casefold()).strip("-")[:20]
    return slug or "guest"


def _email_for(name: str) -> str:
    return f"{_slug(name)}-{secrets.token_hex(3)}@memories.local"


def _name_key(name: str) -> str:
    return name.strip().casefold()


def _join_url(code: str) -> str:
    server = immich_public_url()
    return f"memories://join?code={quote(code, safe='')}&server={quote(server, safe=':/')}"


def _web_url(code: str) -> str:
    return f"{PUBLIC_DIRECTOR}/join/{code}"


def _qr_url(code: str) -> str:
    return f"{PUBLIC_DIRECTOR}/join/{code}/qr.png"


def _load_code(code: str) -> tuple | None:
    _ensure_schema()
    with db._lock:
        return db.conn().execute(
            "SELECT code, album_id, created_by, created_at, expires_at FROM join_codes WHERE code=?",
            (code,),
        ).fetchone()


def _load_redemption(code: str, name_key: str) -> tuple | None:
    _ensure_schema()
    with db._lock:
        return db.conn().execute(
            "SELECT email, password, member_id, album_id, name, language, role "
            "FROM join_redemptions WHERE code=? AND name_key=?",
            (code, name_key),
        ).fetchone()


def qr_png(payload: str) -> bytes:
    image = qrcode.make(payload, box_size=8, border=2)
    buf = BytesIO()
    image.save(buf, format="PNG")
    return buf.getvalue()


def _page(code: str, album_id: str, expired: bool) -> str:
    link = _join_url(code)
    safe_code = escape(code)
    safe_link = escape(link, quote=True)
    if expired:
        status = "<p class=\"bad\">This invite has expired. Ask the host for a new QR code.</p>"
    else:
        status = "<p>This code is valid for 7 days.</p>"
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Join Memories</title>
<style>
body {{ font-family: Georgia, serif; background:#1c1410; color:#f6efe6; margin:0; }}
main {{ max-width: 28rem; margin: 0 auto; padding: 2rem 1.25rem 3rem; }}
h1 {{ font-weight: normal; font-size: 1.8rem; margin-bottom: 0.25rem; }}
img {{ width: 240px; height: 240px; background:#fff; padding: 8px; border-radius: 8px; }}
code {{ font-size: 1.4rem; letter-spacing: 0.12em; }}
a {{ color: #f0c674; }}
ol {{ padding-left: 1.2rem; line-height: 1.45; }}
.bad {{ color: #ffb4a2; }}
</style>
</head>
<body>
<main>
<h1>Join the album</h1>
{status}
<p>Code <code>{safe_code}</code></p>
<p><img src="qr.png" alt="QR code that opens Memories"></p>
<ol>
<li>Install the Memories Android app (APK shared for this event).</li>
<li>Open this page on the phone and tap the link below, or scan the QR code with the app.</li>
<li>The app joins album {escape(album_id)} and you can start shooting.</li>
</ol>
<p><a href="{safe_link}">Open in the Memories app</a></p>
</main>
</body>
</html>
"""


@router.post("/v1/join/{album_id}/invite")
async def create_invite(album_id: str, body: InviteBody | None = None):
    album_id = (album_id or "").strip()
    if not album_id:
        raise HTTPException(400, "album_id required")
    created_by = None
    if body and body.created_by:
        created_by = body.created_by[:200]
    _ensure_schema()
    now = time.time()
    expires = now + EXPIRY_S
    code = ""
    with db._lock:
        conn = db.conn()
        for _ in range(8):
            candidate = _new_code()
            try:
                conn.execute(
                    "INSERT INTO join_codes (code, album_id, created_by, created_at, expires_at) VALUES (?,?,?,?,?)",
                    (candidate, album_id, created_by, now, expires),
                )
                conn.commit()
                code = candidate
                break
            except sqlite3.IntegrityError:
                conn.rollback()
        if not code:
            raise HTTPException(500, "could not allocate a join code")
    log.info("join invite album=%s code=%s", album_id, code)
    return {
        "code": code,
        "join_url": _join_url(code),
        "web_url": _web_url(code),
        "qr_png_url": _qr_url(code),
        "expires_at": _iso(expires),
    }


@router.post("/v1/join/redeem")
async def redeem(body: RedeemBody):
    code = body.code.strip()
    name = body.name.strip()
    if not code or not name:
        raise HTTPException(400, "code and name are required")
    language = (body.language or "").strip()
    role = (body.role or "guest").strip() or "guest"
    row = _load_code(code)
    if not row:
        raise HTTPException(404, "join code not found")
    _code, album_id, _created_by, _created_at, expires_at = row
    if expires_at < time.time():
        raise HTTPException(410, "join code expired")
    key = _name_key(name)
    existing = _load_redemption(code, key)
    server_url = immich_public_url()
    if existing:
        email, password, member_id, stored_album, _stored_name, _language, _role = existing
        return {
            "server_url": server_url,
            "email": email,
            "password": password,
            "album_id": stored_album,
            "member_id": member_id,
        }
    settings = get_settings()
    if not settings.immich_api_key or not server_url:
        raise HTTPException(503, "immich is not configured")
    email = _email_for(name)
    password = _new_password()
    gateway = get_immich()
    try:
        member_id = await gateway.create_user(email=email, password=password, name=name)
        await gateway.add_editor(album_id, member_id)
    except ImmichJoinError as exc:
        log.warning("join redeem failed code=%s status=%s", code, exc.status)
        raise HTTPException(502, exc.detail) from exc
    now = time.time()
    with db._lock:
        conn = db.conn()
        again = conn.execute(
            "SELECT email, password, member_id, album_id FROM join_redemptions WHERE code=? AND name_key=?",
            (code, key),
        ).fetchone()
        if again:
            email, password, member_id, album_id = again
        else:
            conn.execute(
                "INSERT INTO join_redemptions (code, name_key, name, language, role, email, password, member_id, album_id, created_at) "
                "VALUES (?,?,?,?,?,?,?,?,?,?)",
                (code, key, name, language, role, email, password, member_id, album_id, now),
            )
            conn.commit()
    log.info("join redeem code=%s member=%s album=%s", code, member_id, album_id)
    return {
        "server_url": server_url,
        "email": email,
        "password": password,
        "album_id": album_id,
        "member_id": member_id,
    }


@router.get("/join/{code}/qr.png")
async def join_qr(code: str):
    row = _load_code(code)
    if not row:
        raise HTTPException(404, "join code not found")
    payload = _join_url(code)
    return Response(content=qr_png(payload), media_type="image/png")


@router.get("/join/{code}", response_class=HTMLResponse)
async def join_page(code: str):
    row = _load_code(code)
    if not row:
        raise HTTPException(404, "join code not found")
    _code, album_id, _created_by, _created_at, expires_at = row
    return HTMLResponse(_page(code, album_id, expired=expires_at < time.time()))
