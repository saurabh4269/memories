import json

import opentimelineio as otio
import pytest

from memories.editor_api import build_edl, clip_timing, rank_alternatives, validate_clips
from memories.otio_export import to_otio_json
from memories.render import XFADE, xfade_offsets

BASE = "https://example.test/director"

CUT = {
    "title": "Diwali night", "cover_asset_id": "p1",
    "music": {"file": "carefree.mp3", "bpm": 95.7, "beat_offset": 0.163, "title": "Carefree", "path": "/x.mp3"},
    "clips": [
        {"asset_id": "v1", "kind": "video", "in_s": 1.5, "out_s": 4.0, "hold_s": 0.0, "caption": "Aarti"},
        {"asset_id": "p1", "kind": "photo", "in_s": 0.0, "out_s": 0.0, "hold_s": 2.4, "caption": ""},
        {"asset_id": "p2", "kind": "photo", "in_s": 0.0, "out_s": 0.0, "hold_s": 1.8, "caption": "Rangoli"},
    ],
}


def test_timing_hard_cuts():
    t, total = clip_timing(CUT["clips"], "cut")
    assert t == [(0.0, 2.5), (2.5, 2.4), (4.9, 1.8)]
    assert total == pytest.approx(6.7)


def test_timing_xfade_matches_renderer():
    t, total = clip_timing(CUT["clips"], "xfade", XFADE)
    durs = [d for _, d in t]
    assert durs == [round(2.5 + XFADE, 3), round(2.4 + XFADE, 3), 1.8]
    # clip k starts where the renderer starts fading it in
    assert [s for s, _ in t[1:]] == pytest.approx(xfade_offsets(durs, XFADE))
    assert total == pytest.approx(sum(durs) - XFADE * (len(durs) - 1))


def test_edl_shape():
    edl = build_edl(CUT, 0, BASE, analysis={"p1": {"subject_center": [0.3, 0.4]}})
    assert edl["duration_s"] == pytest.approx(6.7)
    c0, c1, c2 = edl["clips"]
    assert c0["media_url"] == f"{BASE}/v1/assets/v1/video" and c0["type"] == "video"
    assert c1["media_url"] == f"{BASE}/v1/assets/p1/image?size=preview"
    assert c1["poster_url"].endswith("size=thumbnail")
    assert c1["kenburns"] == {"from": 1.08, "to": 1.0, "focus": [0.3, 0.4]}  # odd index zooms out
    assert c2["kenburns"]["from"] == 1.0
    assert edl["captions"] == [
        {"text": "Aarti", "start_s": 0.0, "duration_s": 2.5, "clip_index": 0, "asset_id": "v1"},
        {"text": "Rangoli", "start_s": 4.9, "duration_s": 1.8, "clip_index": 2, "asset_id": "p2"}]
    assert edl["music"]["url"] == f"{BASE}/v1/music/carefree.mp3" and edl["music"]["start_s"] == 0.163
    assert all(c["media_url"].startswith("https://") for c in edl["clips"])


@pytest.mark.parametrize("transitions", ["cut", "xfade"])
def test_otio_round_trip(transitions):
    edl = build_edl(CUT, 1, BASE, transitions=transitions, xfade=XFADE, durations={"v1": 10.0})
    s = to_otio_json(edl, "t")
    json.loads(s)
    tl = otio.adapters.read_from_string(s, "otio_json")
    video, audio = tl.tracks
    assert [c.media_reference.target_url for c in video] == [c["media_url"] for c in edl["clips"]]
    assert video[0].source_range.start_time.to_seconds() == pytest.approx(1.5)
    assert video[0].source_range.duration.rate == 30
    assert tl.duration().to_seconds() == pytest.approx(6.7, abs=1 / 30)
    assert [video.range_of_child_at_index(i).start_time.to_seconds() for i in range(3)] == pytest.approx(
        [c["start_s"] for c in edl["clips"]], abs=1 / 30)
    assert [m.name for m in video.markers] == ["Aarti", "Rangoli"]
    assert video.markers[1].marked_range.start_time.to_seconds() == pytest.approx(4.9, abs=1 / 30)
    assert audio[0].media_reference.target_url.endswith("carefree.mp3")
    assert audio[0].source_range.duration.to_seconds() == pytest.approx(6.7, abs=1 / 30)


ROWS = {
    "v1": {"id": "v1", "type": "VIDEO", "duration": 5.0, "analysis": {}},
    "p1": {"id": "p1", "type": "IMAGE", "duration": 0.0, "analysis": {}},
    "p3": {"id": "p3", "type": "IMAGE", "duration": 0.0, "analysis": {}},
}


def test_validate_clamps_and_defaults():
    clips, notes = validate_clips(
        [{"asset_id": "v1", "in_s": 4.5, "out_s": 20}, {"asset_id": "p1", "hold_s": 9}, {"asset_id": "p3"}],
        CUT["clips"], ROWS)
    v, p1, p3 = clips
    assert v["in_s"] == pytest.approx(3.8) and v["out_s"] == pytest.approx(5.0)
    assert p1["hold_s"] == 4.5 and p3["hold_s"] == 2.4
    assert v["caption"] == "Aarti"  # kept from the previous version
    assert len(notes) == 2


def test_validate_rejects():
    with pytest.raises(ValueError, match="duplicate"):
        validate_clips([{"asset_id": "p1"}, {"asset_id": "p1"}], [], ROWS)
    with pytest.raises(ValueError, match="not in this album"):
        validate_clips([{"asset_id": "zz"}], [], ROWS)
    with pytest.raises(ValueError):
        validate_clips([], [], ROWS)


def test_alternatives_exclude_used_and_rank_similar():
    rows = [
        {"id": "a", "type": "IMAGE", "time": "2026-11-01T20:00:00", "person_ids": ["n"], "people": ["Nani"],
         "analysis": {"quality": 7, "activity": "aarti"}},
        {"id": "b", "type": "IMAGE", "time": "2026-11-01T20:02:00", "person_ids": ["n"], "people": ["Nani"],
         "analysis": {"quality": 7, "activity": "aarti"}},
        {"id": "c", "type": "IMAGE", "time": "2026-11-01T23:00:00", "person_ids": [], "analysis": {"quality": 8}},
        {"id": "d", "type": "IMAGE", "time": "2026-11-01T20:01:00", "analysis": {"quality": 9, "dup_of": "a"}},
    ]
    alts = rank_alternatives(rows, [{"asset_id": "a"}], 0)
    assert [x["asset_id"] for x in alts] == ["b", "c"]
    assert "Nani" in alts[0]["why"]
