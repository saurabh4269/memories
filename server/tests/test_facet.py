"""Facet integration: fixture Facet SQLite DB -> export -> Immich match -> per-asset scores + API."""
import importlib.util
import json
import sqlite3
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from memories import facet_api, facet_scores

SERVER = Path(__file__).resolve().parents[1]
ALBUM = "alb-1"

# path, filename, date_taken, w, h, aggregate, aesthetic, comp, face_q, eye, sharp, blink,
# burst_group, burst_lead, dup_group, dup_lead, moment, subject_bbox
ROWS = [
    ("/data/photos/h/a.jpg", "a.jpg", "2026:11:25 10:00:00", 4000, 3000, 8.2, 7.9, 7.0, 8.0, 7.5, 7.7, 0, 1, 1, None, 0, "stage_presentation", "[0.6,0.2,0.8,0.7]"),
    ("/data/photos/h/b.jpg", "b.jpg", "2026:11:25 10:00:01", 4000, 3000, 7.0, 7.1, 6.5, 6.0, 5.0, 6.0, 0, 1, 0, None, 0, "stage_presentation", None),
    ("/data/photos/h/c.jpg", "c.jpg", "2026:11:25 11:00:00", 3000, 4000, 4.0, 4.5, 5.0, 3.0, 2.0, 5.5, 1, None, 0, None, 0, "group_photo", None),
    ("/data/photos/h/d.jpg", "d.jpg", "2026:11:25 12:00:00", 4000, 3000, 6.0, 6.0, 6.0, None, None, 6.0, 0, None, 0, 7, 1, "other", None),
    ("/data/photos/h/e.jpg", "e.jpg", "2026:11:25 12:00:05", 4000, 3000, 5.5, 5.5, 5.5, None, None, 5.0, 0, None, 0, 7, 0, "other", None),
    # same file copied into a subfolder: must not displace the top-level original
    ("/data/photos/h/copy/a.jpg", "a.jpg", "2026:11:25 10:00:00", 4000, 3000, 8.2, 7.9, 7.0, 8.0, 7.5, 7.7, 0, 1, 0, None, 0, "stage_presentation", None),
]
ASSETS = [
    {"id": "A", "type": "IMAGE", "originalFileName": "a.jpg", "localDateTime": "2026-11-25T10:00:00.000Z"},
    {"id": "B", "type": "IMAGE", "originalFileName": "B.JPG", "localDateTime": "2026-11-25T10:00:01.000Z"},
    {"id": "C", "type": "IMAGE", "originalFileName": "c.jpg", "localDateTime": "2026-11-25T11:00:00.000Z"},
    {"id": "D", "type": "IMAGE", "originalFileName": "d.jpg", "localDateTime": "2026-11-25T12:00:00.000Z"},
    {"id": "E", "type": "IMAGE", "originalFileName": "e.jpg", "localDateTime": "2026-11-25T12:00:05.000Z"},
    {"id": "V", "type": "VIDEO", "originalFileName": "clip.mp4"},
]


@pytest.fixture
def facet_db(tmp_path):
    db = tmp_path / "photo_scores_pro.db"
    con = sqlite3.connect(db)
    con.execute("""CREATE TABLE photos (path TEXT PRIMARY KEY, filename TEXT, date_taken TEXT,
        image_width INTEGER, image_height INTEGER, aggregate REAL, aesthetic REAL, comp_score REAL,
        face_quality REAL, eye_sharpness REAL, tech_sharpness REAL, is_blink INTEGER,
        burst_group_id INTEGER, is_burst_lead INTEGER, duplicate_group_id INTEGER,
        is_duplicate_lead INTEGER, narrative_moment TEXT, subject_bbox TEXT, thumbnail BLOB)""")
    con.executemany(f"INSERT INTO photos VALUES ({','.join('?' * 18)}, x'00')", ROWS)
    con.commit()
    con.close()
    return db


@pytest.fixture
def raw(facet_db, tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("facet_export", SERVER / "scripts/facet_export.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    doc = mod.export(str(facet_db))
    # stand in for Facet's scene/similarity passes (they need Facet's api package)
    doc["photos"]["/data/photos/h/a.jpg"]["scene_id"] = 1
    doc["photos"]["/data/photos/h/b.jpg"]["scene_id"] = 1
    doc["photos"]["/data/photos/h/d.jpg"]["similarity_group"] = 3
    doc["photos"]["/data/photos/h/e.jpg"]["similarity_group"] = 3
    monkeypatch.setenv("FACET_DIR", str(tmp_path / "facet"))
    rp = tmp_path / "facet" / "facet_raw.json"
    rp.parent.mkdir()
    rp.write_text(json.dumps(doc))
    facet_scores._mem.clear()
    return doc


def test_export_reads_scores_without_blobs(raw):
    assert len(raw["photos"]) == 6
    assert "thumbnail" not in raw["photos"]["/data/photos/h/a.jpg"]


def test_build_scores_signals(raw):
    s = facet_scores.build_scores(raw, ASSETS)
    assert set(s) == {"A", "B", "C", "D", "E"}  # videos never scored
    assert s["A"]["aggregate"] == 8.2 and s["A"]["is_burst_lead"] and s["A"]["burst_group"] == "b1"
    assert not s["B"]["is_burst_lead"] and s["B"]["cull_reasons"] == ["burst_non_lead"]
    assert s["C"]["blink"] and s["C"]["cull"] and s["C"]["burst_group"] is None and s["C"]["is_burst_lead"]
    assert s["E"]["duplicate_of"] == "D" and s["D"]["duplicate_of"] is None and not s["D"]["cull"]
    assert s["D"]["moment_labels"] == [] and s["A"]["moment_labels"] == ["stage_presentation"]
    assert s["A"]["subject_box"] == [0.6, 0.2, 0.8, 0.7]
    x0, y0, x1, y1 = s["A"]["crop_9x16"]
    assert y0 == 0 and y1 == 1 and x0 <= 0.6 and x1 >= 0.65  # 9:16 window centred on the subject
    assert abs((x1 - x0) * 4000 / 3000 - 9 / 16) < 1e-3
    assert s["A"]["scene_id"] == 1 and s["D"]["similarity_group"] == "s3"


def test_refresh_cache_and_load(raw):
    doc = facet_scores.refresh_scores(ALBUM, assets=ASSETS)
    assert doc["summary"]["scored"] == 5 and doc["summary"]["top"][0]["asset_id"] == "A"
    assert doc["summary"]["culled"] == 3 and doc["album_videos"] == 1
    assert facet_scores.cache_path(ALBUM).exists()
    scores = facet_scores.load_scores(ALBUM)
    assert scores["A"]["aggregate"] == 8.2
    assert facet_scores.shot_value("A", 0.5, scores) == pytest.approx(0.4 * 0.82 + 0.6 * 0.5)
    assert facet_scores.shot_value("V", 0.5, scores) == 0.5


def test_api(raw, monkeypatch):
    monkeypatch.setattr(facet_scores, "fetch_album_assets", lambda album_id: ASSETS)
    app = FastAPI()
    app.include_router(facet_api.router)
    c = TestClient(app)
    r = c.post(f"/v1/albums/{ALBUM}/facet/refresh")
    assert r.status_code == 200 and r.json()["summary"]["scored"] == 5
    r = c.get(f"/v1/albums/{ALBUM}/facet")
    assert r.status_code == 200 and r.json()["scores"]["C"]["blink"] is True
    assert "scores" not in c.get(f"/v1/albums/{ALBUM}/facet?summary_only=true").json()
