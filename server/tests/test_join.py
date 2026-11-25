"""Join invite + redeem. Immich is mocked; no network."""
import asyncio
import io
import json
import time
import uuid

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image

from memories import db, join_api
from memories.config import get_settings


ALBUM = "47e3d2d0-21fa-4df7-8a2e-44f57597524b"
PUBLIC = "https://memories-3870f5.centralindia.cloudapp.azure.com/director"


@pytest.fixture(autouse=True)
def isolated_db(tmp_path, monkeypatch):
    monkeypatch.setenv("DATA_DIR", str(tmp_path))
    monkeypatch.setenv("IMMICH_URL", "https://photos.example")
    monkeypatch.setenv("IMMICH_API_KEY", "test-key")
    monkeypatch.setenv("PUBLIC_BASE_URL", PUBLIC)
    get_settings.cache_clear()
    join_api._schema_ready = False
    if db._conn is not None:
        db._conn.close()
        db._conn = None
    yield
    get_settings.cache_clear()
    join_api._schema_ready = False
    if db._conn is not None:
        db._conn.close()
        db._conn = None


class FakeImmich:
    def __init__(self):
        self.created: list[dict] = []
        self.shared: list[dict] = []

    async def create_user(self, *, email, password, name):
        user_id = str(uuid.uuid4())
        self.created.append({"id": user_id, "email": email, "password": password, "name": name})
        return user_id

    async def add_editor(self, album_id, user_id):
        self.shared.append({"album_id": album_id, "userId": user_id, "role": "editor"})


@pytest.fixture
def fake():
    return FakeImmich()


@pytest.fixture
def client(fake, monkeypatch):
    monkeypatch.setattr(join_api, "get_immich", lambda: fake)
    app = FastAPI()
    app.include_router(join_api.router)
    return TestClient(app)


def test_loopback_immich_url_is_the_public_host(monkeypatch):
    monkeypatch.setenv("IMMICH_URL", "http://127.0.0.1:2283")
    get_settings.cache_clear()
    assert join_api.immich_public_url() == "https://memories-3870f5.centralindia.cloudapp.azure.com"


def test_invite_shape(client):
    response = client.post(f"/v1/join/{ALBUM}/invite", json={"created_by": "host"})
    assert response.status_code == 200
    body = response.json()
    code = body["code"]
    assert len(code) == 8
    assert set(code) <= set(join_api._CODE_ALPHABET)
    assert body["join_url"] == f"memories://join?code={code}&server=https://photos.example"
    assert body["web_url"] == f"{PUBLIC}/join/{code}"
    assert body["qr_png_url"] == f"{PUBLIC}/join/{code}/qr.png"
    expires = time.strptime(body["expires_at"], "%Y-%m-%dT%H:%M:%SZ")
    assert expires.tm_year >= 2026
    row = db.conn().execute("SELECT album_id, created_by FROM join_codes WHERE code=?", (code,)).fetchone()
    assert row == (ALBUM, "host")


def test_qr_png_and_html(client):
    code = client.post(f"/v1/join/{ALBUM}/invite", json={}).json()["code"]
    png = client.get(f"/join/{code}/qr.png")
    assert png.status_code == 200
    assert png.headers["content-type"].startswith("image/png")
    assert png.content[:8] == b"\x89PNG\r\n\x1a\n"
    image = Image.open(io.BytesIO(png.content))
    assert image.format == "PNG"
    assert image.size[0] == image.size[1]
    page = client.get(f"/join/{code}")
    assert page.status_code == 200
    assert "text/html" in page.headers["content-type"]
    assert "APK" in page.text
    assert code in page.text
    assert 'src="qr.png"' in page.text
    assert "memories://join?code=" in page.text
    assert client.get("/join/missingcode").status_code == 404
    assert client.get("/join/missingcode/qr.png").status_code == 404


def test_redeem_creates_editor_and_is_idempotent(client, fake):
    code = client.post(f"/v1/join/{ALBUM}/invite", json={}).json()["code"]
    payload = {"code": code, "name": "Nani", "language": "hi-IN", "role": "elder"}
    first = client.post("/v1/join/redeem", json=payload)
    assert first.status_code == 200
    body = first.json()
    assert body["server_url"] == "https://photos.example"
    assert body["album_id"] == ALBUM
    assert body["email"].startswith("nani-") and body["email"].endswith("@memories.local")
    assert len(body["password"]) == 16
    assert body["member_id"] == fake.created[0]["id"]
    assert fake.created[0]["name"] == "Nani"
    assert fake.created[0]["password"] == body["password"]
    assert fake.shared == [{"album_id": ALBUM, "userId": body["member_id"], "role": "editor"}]
    stored = db.conn().execute(
        "SELECT name, language, role FROM join_redemptions WHERE code=?", (code,)
    ).fetchone()
    assert stored == ("Nani", "hi-IN", "elder")

    again = client.post("/v1/join/redeem", json={**payload, "name": " nani "})
    assert again.status_code == 200
    assert again.json() == body
    assert len(fake.created) == 1
    assert len(fake.shared) == 1

    other = client.post("/v1/join/redeem", json={**payload, "name": "Dadi"})
    assert other.status_code == 200
    assert other.json()["email"].startswith("dadi-")
    assert other.json()["member_id"] != body["member_id"]
    assert len(fake.created) == 2


def test_redeem_unknown_and_expired(client, fake):
    missing = client.post("/v1/join/redeem", json={"code": "nosuch", "name": "Nani", "language": "hi", "role": "guest"})
    assert missing.status_code == 404
    code = client.post(f"/v1/join/{ALBUM}/invite", json={}).json()["code"]
    with db._lock:
        db.conn().execute("UPDATE join_codes SET expires_at=? WHERE code=?", (time.time() - 5, code))
        db.conn().commit()
    expired = client.post("/v1/join/redeem", json={"code": code, "name": "Nani", "language": "en", "role": "guest"})
    assert expired.status_code == 410
    assert fake.created == []
    blank = client.post("/v1/join/redeem", json={"code": code, "name": "   "})
    assert blank.status_code == 400


def test_immich_gateway_contract():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.path == "/api/admin/users":
            return httpx.Response(201, json={"id": "11111111-1111-4111-8111-111111111111", "email": "nani-aa@memories.local", "name": "Nani"})
        return httpx.Response(200, json={"id": ALBUM})

    transport = httpx.MockTransport(handler)
    http = httpx.AsyncClient(transport=transport)
    gateway = join_api.ImmichJoinGateway(client=http, api="https://immich.example/api", api_key="admin-key")

    async def run():
        user_id = await gateway.create_user(email="nani-aa@memories.local", password="Abcdefghij123456", name="Nani")
        await gateway.add_editor(ALBUM, user_id)
        return user_id

    user_id = asyncio.run(run())
    assert user_id == "11111111-1111-4111-8111-111111111111"
    create, share = seen
    assert create.method == "POST"
    assert create.url.path == "/api/admin/users"
    assert create.headers["x-api-key"] == "admin-key"
    assert json.loads(create.content) == {
        "email": "nani-aa@memories.local",
        "password": "Abcdefghij123456",
        "name": "Nani",
        "notify": False,
        "shouldChangePassword": False,
    }
    assert share.method == "PUT"
    assert share.url.path == f"/api/albums/{ALBUM}/users"
    assert share.headers["x-api-key"] == "admin-key"
    assert json.loads(share.content) == {
        "albumUsers": [{"userId": "11111111-1111-4111-8111-111111111111", "role": "editor"}],
    }
