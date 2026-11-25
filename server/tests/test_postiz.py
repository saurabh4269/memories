"""Postiz posting endpoints with a mocked Postiz Public API (no network)."""
import json

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from memories import pipeline, postiz_api

INTEGRATIONS = [
    {"id": "bs1", "name": "memories.bsky.social", "identifier": "bluesky", "picture": "https://x/a.png", "disabled": False},
    {"id": "dc1", "name": "Family server", "identifier": "discord", "picture": None, "disabled": False},
    {"id": "tg1", "name": "Family channel", "identifier": "telegram", "picture": None, "disabled": False},
]


class Postiz:
    def __init__(self):
        self.calls = []

    def __call__(self, req: httpx.Request) -> httpx.Response:
        self.calls.append(req)
        if req.url.host == "director.example":
            assert "authorization" not in req.headers  # never leak the Postiz key elsewhere
            return httpx.Response(200, content=b"MP4DATA-remote")
        assert req.headers["authorization"] == "KEY123"  # raw key, no Bearer
        path = req.url.path
        if path.endswith("/integrations"):
            return httpx.Response(200, json=INTEGRATIONS)
        if path.endswith("/upload"):
            assert b'name="file"' in req.content and b"MP4DATA" in req.content
            return httpx.Response(200, json={"id": "m1", "path": "https://postiz.example/uploads/r.mp4"})
        if path.endswith("/posts"):
            body = json.loads(req.content)
            integ = body["posts"][0]["integration"]["id"]
            if integ == "tg1":
                return httpx.Response(400, json={"message": "bad telegram"})
            return httpx.Response(200, json=[{"postId": f"p-{integ}", "integration": integ}])
        return httpx.Response(404)


@pytest.fixture
def env(monkeypatch, tmp_path):
    monkeypatch.setenv("POSTIZ_URL", "https://postiz.example/")
    monkeypatch.setenv("POSTIZ_API_KEY", "KEY123")
    monkeypatch.delenv("POSTIZ_DISCORD_CHANNEL", raising=False)
    mock = Postiz()
    monkeypatch.setattr(postiz_api, "_transport", httpx.MockTransport(mock))
    mp4 = tmp_path / "cut0_final.mp4"
    mp4.write_bytes(b"MP4DATA")
    reel = {"reel_id": "r1", "album_id": "a1", "cuts": [
        {"title": "Diwali night", "final_status": "done", "final": {"path": str(mp4), "url": "https://director.example/f.mp4"}},
        {"title": "Remote", "final_status": "done", "final": {"path": "/nope.mp4", "url": "https://director.example/f.mp4"}},
        {"title": "Pending", "final_status": "pending"},
    ]}
    monkeypatch.setattr(pipeline, "load", lambda rid: reel if rid == "r1" else None)
    app = FastAPI()
    app.include_router(postiz_api.router)
    return TestClient(app), mock


def test_channels(env):
    client, mock = env
    r = client.get("/v1/post/channels")
    assert r.status_code == 200
    ch = r.json()["channels"]
    assert ch[0] == {"id": "bs1", "provider": "bluesky", "name": "memories.bsky.social",
                     "avatar": "https://x/a.png", "disabled": False}
    assert str(mock.calls[0].url) == "https://postiz.example/api/public/v1/integrations"


def test_post_statuses(env):
    client, mock = env
    r = client.post("/v1/reels/r1/post", json={"cut": 0, "channel_ids": ["bs1", "dc1", "tg1", "zz"],
                                               "caption": "Happy Diwali"})
    assert r.status_code == 200, r.text
    posts = {p["channel"]: p for p in r.json()["posts"]}
    assert posts["bs1"]["status"] == "queued" and posts["bs1"]["post_id"] == "p-bs1"
    assert posts["dc1"]["status"] == "error" and "channel" in posts["dc1"]["error"]  # discord needs a channel
    assert posts["tg1"]["status"] == "error" and "bad telegram" in posts["tg1"]["error"]
    assert posts["zz"]["error"] == "unknown channel"
    sent = [json.loads(c.content) for c in mock.calls if c.url.path.endswith("/posts")]
    bs = next(b for b in sent if b["posts"][0]["integration"]["id"] == "bs1")
    assert bs["type"] == "now" and bs["shortLink"] is False and bs["date"].endswith("Z")
    assert bs["posts"][0]["settings"] == {"__type": "bluesky"}
    assert bs["posts"][0]["value"] == [{"content": "Happy Diwali",
                                        "image": [{"id": "m1", "path": "https://postiz.example/uploads/r.mp4"}]}]
    assert sum(c.url.path.endswith("/upload") for c in mock.calls) == 1  # one upload shared by all channels


def test_discord_channel_override_and_remote_final(env):
    client, mock = env
    r = client.post("/v1/reels/r1/post", json={"cut": 1, "channel_ids": ["dc1"],
                                               "settings": {"dc1": {"channel": "987"}}})
    assert r.status_code == 200, r.text
    p = r.json()["posts"][0]
    assert p["status"] == "queued"
    body = json.loads(next(c for c in mock.calls if c.url.path.endswith("/posts")).content)
    assert body["posts"][0]["settings"] == {"__type": "discord", "channel": "987"}
    assert body["posts"][0]["value"][0]["content"] == "Remote"  # caption falls back to cut title
    assert any(c.url.host == "director.example" for c in mock.calls)


def test_errors(env, monkeypatch):
    client, _ = env
    assert client.post("/v1/reels/nope/post", json={"channel_ids": ["bs1"]}).status_code == 404
    assert client.post("/v1/reels/r1/post", json={"cut": 9, "channel_ids": ["bs1"]}).status_code == 400
    assert client.post("/v1/reels/r1/post", json={"cut": 0, "channel_ids": []}).status_code == 400
    monkeypatch.delenv("POSTIZ_API_KEY")
    assert client.get("/v1/post/channels").status_code == 503


def test_default_settings():
    assert postiz_api.default_settings("youtube", "Title line\nmore")["title"] == "Title line"
    assert postiz_api.default_settings("telegram", "x") == {"__type": "telegram"}
