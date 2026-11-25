"""Unit tests for the Sarvam extras: parsing, normalisation, validation, error mapping (no network)."""
import asyncio
import io
import wave

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image

from memories import extras_api
from memories.dictate import (audio_kind, build_vocabulary, keyterms, normalize_intent, sniff_audio)
from memories.extras_common import ExtrasInputError, as_str_list
from memories.invite import (guess_language, normalize_date, normalize_invite, normalize_shot_list,
                             normalize_time, prepare_image)
from memories.sarvam import SarvamAuthError, SarvamError, SarvamQuotaError
from memories.voiceover import V4_FLASH_SPEAKERS, validate_speaker


# ---------------------------------------------------------------- invite

@pytest.mark.parametrize("raw,exp", [
    ("2026-12-12", "2026-12-12"), ("12/12/2026", "2026-12-12"), ("१२-१२-२०२६", "2026-12-12"),
    ("12 दिसम्बर 2026", "2026-12-12"), ("Saturday, 5th Nov 2026", "2026-11-05"), ("", ""),
    ("शुभ मुहूर्त", "शुभ मुहूर्त"),
])
def test_normalize_date(raw, exp):
    assert normalize_date(raw) == exp


@pytest.mark.parametrize("raw,exp", [
    ("19:00", "19:00"), ("7:30 PM", "19:30"), ("सायं 7:00 बजे", "19:00"), ("प्रातः 10 बजे", "10:00"),
    ("रात्रि १०:३० बजे", "22:30"), ("12 am", "00:00"), ("7.15 pm", "19:15"), ("", ""), ("शुभ बेला", "शुभ बेला"),
])
def test_normalize_time(raw, exp):
    assert normalize_time(raw) == exp


def test_normalize_invite_full():
    raw = {"result": {
        "event_name": " शुभ विवाह ", "event_type": "Wedding",
        "hosts": ["श्री रमेश शर्मा", "श्री रमेश शर्मा", None],
        "family_names": ["श्री रमेश शर्मा", "दादी कमला देवी", "null"],
        "venue": "होटल राजमहल, जयपुर",
        "ceremonies": [{"name": "हल्दी", "name_en": "Haldi", "date": "12/12/2026", "time": "प्रातः 10 बजे"},
                       "फेरे", {"name": ""}, 5],
        "language": "Hindi"}}
    inv = normalize_invite(raw)
    assert inv["event_name"] == "शुभ विवाह" and inv["event_type"] == "wedding"
    assert inv["hosts"] == ["श्री रमेश शर्मा"]
    assert inv["family_names"] == ["दादी कमला देवी"]  # host removed, "null" dropped
    assert inv["ceremonies"][0] == {"name": "हल्दी", "name_en": "Haldi", "date": "2026-12-12", "time": "10:00"}
    assert inv["ceremonies"][1]["name"] == "फेरे" and len(inv["ceremonies"]) == 2
    assert inv["language"] == "hi-IN"


def test_normalize_invite_garbage_never_raises():
    assert normalize_invite(None)["ceremonies"] == []
    assert normalize_invite({"ceremonies": "x"})["ceremonies"] == []
    assert normalize_invite({"event_name": "Diwali Milan", "language": "xx"})["language"] == "en-IN"


def test_guess_language():
    assert guess_language("शुभ विवाह") == "hi-IN"
    assert guess_language("திருமணம்") == "ta-IN"
    assert guess_language("Wedding") == "en-IN"
    assert guess_language("") == "hi-IN"


def test_normalize_shot_list_ids_and_ceremony_snap():
    inv = {"ceremonies": [{"name": "मेहंदी एवं संगीत", "name_en": "Mehendi and Sangeet"}]}
    raw = {"shots": [
        {"id": "Mehendi Hands!", "label_en": "Mehendi close-up", "label_local": "मेहंदी", "why": "w",
         "ceremony": "Mehendi and Sangeit"},
        {"id": "mehendi_hands", "label_en": "Bride's hands", "label_local": "", "why": "", "ceremony": ""},
        {"label_en": ""}, "junk",
    ]}
    shots = normalize_shot_list(raw, inv)
    assert [s["id"] for s in shots] == ["mehendi_hands", "mehendi_hands_2"]
    assert shots[0]["ceremony"] == "Mehendi and Sangeet"
    assert shots[1]["ceremony"] == "general" and shots[1]["label_local"] == "Bride's hands"
    assert normalize_shot_list({"nope": 1}) == []


def test_prepare_image_png_rgba_to_jpeg_and_errors():
    buf = io.BytesIO()
    Image.new("RGBA", (3000, 1000), (255, 0, 0, 128)).save(buf, "PNG")
    out = prepare_image(buf.getvalue())
    im = Image.open(io.BytesIO(out))
    assert im.format == "JPEG" and max(im.size) == 2200
    with pytest.raises(ExtrasInputError) as e:
        prepare_image(b"hello")
    assert e.value.status == 415
    with pytest.raises(ExtrasInputError):
        prepare_image(b"")


# ---------------------------------------------------------------- dictate

def _wav() -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(16000), w.writeframes(b"\0\0" * 1600)
    return buf.getvalue()


def test_audio_kind_strips_codecs_and_sniffs():
    assert audio_kind("audio/webm;codecs=opus", None, b"") == ("webm", "audio/webm")
    assert audio_kind("audio/mp4; codecs=mp4a.40.2", None, b"") == ("m4a", "audio/mp4")
    assert audio_kind("audio/x-m4a", None, b"") == ("m4a", "audio/mp4")
    assert audio_kind("audio/aac", None, b"") == ("aac", "audio/aac")
    assert audio_kind("application/octet-stream", "rec.m4a", b"") == ("m4a", "audio/mp4")
    assert audio_kind(None, None, _wav()) == ("wav", "audio/wav")
    assert sniff_audio(b"\x00\x00\x00\x20ftypM4A ") == "m4a"
    assert sniff_audio(b"\x1a\x45\xdf\xa3....") == "webm"
    assert sniff_audio(b"\xff\xf1\x50\x80") == "aac"
    with pytest.raises(ExtrasInputError) as e:
        audio_kind("application/octet-stream", "x.bin", b"garbage")
    assert e.value.status == 415


def test_vocabulary_has_required_terms_and_unique_sounds_like():
    v = build_vocabulary(["Pihu", "Chintu", "", "बबली मौसी"])
    words = [e["word"] for e in v]
    for w in ["reel", "status", "story", "WhatsApp", "Instagram", "Nani", "Dadi", "Nana", "Dada", "Mummy", "Papa",
              "Chintu", "bhaiya", "didi", "रील", "Pihu", "बबली मौसी"]:
        assert w in words
    assert words.count("Chintu") == 1
    sl = [s for e in v for s in e.get("sounds_like", [])]
    assert len(sl) == len(set(sl)), "a sounds_like on two entries is a Dictate 400"
    assert all(isinstance(e, dict) and "word" in e for e in v)
    assert {"व्हील"} <= set(sl)
    assert "रील" in keyterms() and len(keyterms([f"n{i}" for i in range(100)])) == 50


def test_normalize_intent():
    it = normalize_intent({"request": "Make a reel", "people": ["दादी", "chintu", "Dadi"], "include": "aarti, rangoli",
                           "exclude": None, "mood": "Joyful", "music": "null", "destination": "WhatsApp Status"},
                          "दादी और चिंटू की रील", names=["Chintu"])
    assert it["people"] == ["Dadi", "Chintu"]
    assert it["include"] == ["aarti", "rangoli"] and it["exclude"] == []
    assert it["mood"] == "joyful" and it["music"] is None and it["destination"] == "status"
    # destination inferred from transcript when model leaves it out
    it2 = normalize_intent({"destination": None}, "इंस्टाग्राम story के लिए")
    assert it2["destination"] == "story" and it2["request"] == "इंस्टाग्राम story के लिए"
    assert normalize_intent("garbage", "")["people"] == []


def test_as_str_list():
    assert as_str_list("a; b, a") == ["a", "b"]
    assert as_str_list([{"name": "X"}, None, "none", 3]) == ["X", "3"]


# ---------------------------------------------------------------- voiceover

def test_validate_speaker():
    for sp in ["simran_hi_narration", "roopa_hi_narration", "ratan_hi_latenight_warm"]:
        assert sp in V4_FLASH_SPEAKERS and validate_speaker(sp, "hi-IN") == sp
    assert validate_speaker(None, "en-IN") == "simran_hi_narration"
    with pytest.raises(ExtrasInputError):
        validate_speaker("shubh", "hi-IN")  # bulbul:v3 voice, not v4-flash
    with pytest.raises(ExtrasInputError):
        validate_speaker("simran_hi_narration", "fr-FR")


# ---------------------------------------------------------------- API error mapping

class Boom:
    def __init__(self, exc):
        self.exc = exc

    async def translate(self, *a, **k):
        raise self.exc


@pytest.mark.parametrize("exc,status,code", [
    (SarvamQuotaError("402: no credits"), 402, "sarvam_quota"),
    (SarvamAuthError("Sarvam auth failed (403)"), 502, "sarvam_auth"),
    (SarvamError("retries exhausted: 429: slow down"), 429, "sarvam_rate_limited"),
    (SarvamError("400: bad"), 502, "sarvam_error"),
    (asyncio.TimeoutError(), 504, "timeout"),
])
def test_error_mapping(exc, status, code, tmp_path, monkeypatch):
    from memories import voiceover
    monkeypatch.setattr(voiceover, "cache_get", lambda *a: None)
    app = FastAPI()
    app.include_router(extras_api.router)
    app.dependency_overrides[extras_api.get_sarvam] = lambda: Boom(exc)
    r = TestClient(app).post("/v1/extras/translate", json={"text": "hello there", "target": "hi-IN"})
    assert r.status_code == status
    j = r.json()
    assert j["error"] == code and "total" in j["timings_ms"] and isinstance(j["calls"], list)
    if status == 429:
        assert r.headers["retry-after"]


def test_bad_inputs_are_4xx():
    app = FastAPI()
    app.include_router(extras_api.router)
    app.dependency_overrides[extras_api.get_sarvam] = lambda: Boom(RuntimeError("must not be called"))
    c = TestClient(app)
    assert c.post("/v1/extras/voiceover", json={"text": "hi", "speaker": "nobody"}).status_code == 400
    assert c.post("/v1/extras/voiceover", json={"text": "hi", "language": "fr-FR"}).status_code == 400
    assert c.post("/v1/extras/translate", json={"text": "hi", "target": "xx"}).status_code == 400
    r = c.post("/v1/extras/voice-prompt", files={"audio": ("a.bin", b"junk", "application/octet-stream")})
    assert r.status_code == 415
    r = c.post("/v1/extras/invite", files={"image": ("a.jpg", b"junk", "image/jpeg")}, data={"refresh": "true"})
    assert r.status_code == 415
    assert extras_api._names('["Pihu", " ", "Chintu"]') == ["Pihu", "Chintu"]
    assert extras_api._names("Pihu, Chintu") == ["Pihu", "Chintu"]
