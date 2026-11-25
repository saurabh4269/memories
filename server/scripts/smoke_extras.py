"""Live smoke test for the Sarvam extras (real API, no mocks). Run from server/:

    .venv/bin/python scripts/smoke_extras.py

1. renders a Hindi wedding invite with Pillow + Noto Sans Devanagari -> POST /v1/extras/invite
2. bulbul voiceover + elder confirmation -> POST /v1/extras/voiceover, /confirmation
3. generates the Hindi voice prompt with bulbul (wav), converts to m4a/webm with ffmpeg,
   -> POST /v1/extras/voice-prompt (wav, m4a with ';codecs=' content type, webm)
4. mayura translate -> POST /v1/extras/translate
Exits non-zero on any failed check. Prints results and timings.
"""
from __future__ import annotations

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw, ImageFont, features

from memories.config import get_settings
from memories.extras_api import router

FONT = get_settings().assets_dir / "fonts" / "NotoSansDevanagari-Bold.ttf"
PROMPT_HI = "दादी और बच्चों वाली रील बना दो, स्टेटस के लिए"
FAILS: list[str] = []


def check(cond: bool, msg: str) -> None:
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond:
        FAILS.append(msg)


def make_invite() -> bytes:
    if not features.check("raqm"):
        print("WARNING: Pillow without libraqm, Devanagari will not be shaped correctly")
    W, H = 1080, 1500
    im = Image.new("RGB", (W, H), (255, 248, 231))
    d = ImageDraw.Draw(im)
    d.rectangle([30, 30, W - 30, H - 30], outline=(190, 30, 45), width=10)
    d.rectangle([55, 55, W - 55, H - 55], outline=(212, 160, 23), width=4)

    def f(sz):
        return ImageFont.truetype(str(FONT), sz)

    y = 110
    lines = [
        ("॥ श्री गणेशाय नमः ॥", 40, (190, 30, 45)),
        ("शुभ विवाह", 96, (150, 20, 30)),
        ("चि. राहुल संग सौ. प्रिया", 58, (60, 30, 10)),
        ("", 20, None),
        ("निवेदक: श्रीमती सुनीता एवं श्री रमेश शर्मा", 40, (60, 30, 10)),
        ("आशीर्वाद: दादी श्रीमती कमला देवी, नानी श्रीमती शकुंतला जी", 34, (60, 30, 10)),
        ("", 30, None),
        ("मांगलिक कार्यक्रम", 52, (190, 30, 45)),
        ("हल्दी — 12 दिसम्बर 2026, प्रातः 10:00 बजे", 40, (60, 30, 10)),
        ("मेहंदी एवं संगीत — 12 दिसम्बर 2026, सायं 7:00 बजे", 40, (60, 30, 10)),
        ("बारात प्रस्थान — 13 दिसम्बर 2026, सायं 6:00 बजे", 40, (60, 30, 10)),
        ("फेरे — 13 दिसम्बर 2026, रात्रि 10:30 बजे", 40, (60, 30, 10)),
        ("", 30, None),
        ("स्थान: होटल राजमहल पैलेस, सिविल लाइन्स, जयपुर", 40, (60, 30, 10)),
        ("", 20, None),
        ("आपकी उपस्थिति प्रार्थनीय है", 44, (150, 20, 30)),
    ]
    for text, sz, col in lines:
        if text:
            fo = f(sz)
            w = d.textlength(text, font=fo)
            d.text(((W - w) / 2, y), text, font=fo, fill=col)
        y += int(sz * 1.6)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=92)
    return buf.getvalue()


def show(label: str, r) -> dict:
    j = r.json()
    calls = ", ".join(f"{c['kind']}:{c['ms']}ms{'' if c['ok'] else '!' + str(c.get('status', c.get('error')))}"
                      for c in j.get("calls", []))
    print(f"\n== {label}: HTTP {r.status_code}  timings_ms={j.get('timings_ms')}\n   calls: {calls}")
    return j


def main() -> int:
    out_dir = Path(tempfile.mkdtemp(prefix="smoke_extras_"))
    app = FastAPI()
    app.include_router(router)
    report: dict = {}
    with TestClient(app) as c:
        # ---------------- 1. invite
        img = make_invite()
        (out_dir / "invite.jpg").write_bytes(img)
        t0 = time.perf_counter()
        r = c.post("/v1/extras/invite", files={"image": ("invite.jpg", img, "image/jpeg")},
                   data={"album_id": "smoke-album", "refresh": "false" if os.environ.get("SMOKE_CACHED") else "true"})
        j = show("invite", r)
        report["invite_wall_ms"] = round((time.perf_counter() - t0) * 1000)
        check(r.status_code == 200, "invite 200")
        if r.status_code == 200:
            inv = j["invite"]
            print(json.dumps(inv, ensure_ascii=False, indent=1))
            print("   shot list:")
            for s in j["shot_list"]:
                print(f"    - [{s['ceremony']}] {s['label_en']} / {s['label_local']}  ({s['why']})")
            check(len(inv["ceremonies"]) >= 3, f"≥3 ceremonies ({len(inv['ceremonies'])})")
            check(any(cer["date"] == "2026-12-12" for cer in inv["ceremonies"]), "ISO date 2026-12-12 present")
            check(any(cer["time"] == "19:00" for cer in inv["ceremonies"]), "24h time 19:00 present")
            check(inv["language"] == "hi-IN", f"language hi-IN ({inv['language']})")
            check(len(j["shot_list"]) >= 6, f"≥6 shots ({len(j['shot_list'])})")
            check(any("haldi" in s["ceremony"].lower() for s in j["shot_list"]), "a Haldi shot")
            r2 = c.post("/v1/extras/invite", files={"image": ("invite.jpg", img, "image/jpeg")})
            j2 = show("invite (cached)", r2)
            check(r2.status_code == 200 and j2.get("cached") is True, "invite cache hit")
            r3 = c.get("/v1/extras/invite/smoke-album")
            check(r3.status_code == 200 and r3.json()["shot_list"], "invite stored for album")

        # ---------------- 2. voiceover + confirmation
        for sp in ["simran_hi_narration", "roopa_hi_narration", "ratan_hi_latenight_warm"]:
            r = c.post("/v1/extras/voiceover", json={
                "text": "इस दिवाली, दादी की मुस्कान और बच्चों की फुलझड़ियाँ... हमारे परिवार की सबसे प्यारी यादें।",
                "language": "hi-IN", "speaker": sp})
            j = show(f"voiceover {sp}", r)
            check(r.status_code == 200 and j.get("duration_s", 0) > 1 and Path(j["path"]).exists(),
                  f"voiceover {sp}: {j.get('duration_s')} s {j.get('path')}")
        r = c.post("/v1/extras/voiceover", json={"text": "Our Diwali, our family.", "language": "en-IN",
                                                 "speaker": "simran_en_narration", "codec": "wav"})
        j = show("voiceover en-IN wav", r)
        check(r.status_code == 200 and j.get("duration_s", 0) > 0.5, f"en wav {j.get('duration_s')} s")
        r = c.post("/v1/extras/voiceover", json={"text": "x", "speaker": "not_a_voice"})
        j = show("voiceover bad speaker", r)
        check(r.status_code == 400 and j["error"] == "bad_request", "bad speaker -> 400")
        r = c.post("/v1/extras/confirmation", json={"language": "hi-IN", "speaker": "roopa_hi_narration"})
        j = show("confirmation hi-IN", r)
        check(r.status_code == 200 and j["text"].startswith("आपकी रील तैयार है"), f"confirmation {j.get('path')}")
        r = c.post("/v1/extras/confirmation", json={"language": "ta-IN", "speaker": "gokul_ta_narration"})
        j = show("confirmation ta-IN (translated)", r)
        check(r.status_code == 200, f"ta confirmation: {j.get('text')}")

        # ---------------- 3. voice prompt
        r = c.post("/v1/extras/voiceover", json={"text": PROMPT_HI, "language": "hi-IN",
                                                 "speaker": "kavya_hi_conversational", "codec": "wav", "pace": 1.0})
        check(r.status_code == 200, "generated Hindi voice prompt (bulbul wav)")
        wav = Path(r.json()["path"]).read_bytes()
        variants = [("prompt.wav", wav, "audio/wav")]
        if shutil.which("ffmpeg"):
            src = out_dir / "prompt.wav"
            src.write_bytes(wav)
            for ext, args, ct in [("m4a", ["-c:a", "aac", "-b:a", "64k"], "audio/mp4;codecs=mp4a.40.2"),
                                  ("webm", ["-c:a", "libopus", "-b:a", "32k"], "audio/webm;codecs=opus")]:
                dst = out_dir / f"prompt.{ext}"
                subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), *args, str(dst)], check=True)
                variants.append((dst.name, dst.read_bytes(), ct))
        for fname, data, ct in variants:
            r = c.post("/v1/extras/voice-prompt", files={"audio": (fname, data, ct)},
                       data={"names": "Pihu, Chintu", "language": "hi-IN"})
            j = show(f"voice-prompt {fname} ({ct})", r)
            if r.status_code == 200:
                it = j["intent"]
                print("   engine:", j["engine_used"], "\n   intent:", json.dumps(it, ensure_ascii=False))
                check("Dadi" in it["people"] or any("दादी" in p or "grand" in p.lower() for p in it["people"]),
                      f"{fname}: Dadi in people {it['people']}")
                check(it["destination"] == "status", f"{fname}: destination status ({it['destination']})")
                check("व्हील" not in it["transcript"], f"{fname}: no 'wheel' mishearing")
            else:
                check(False, f"{fname}: {j}")
        r = c.post("/v1/extras/voice-prompt", files={"audio": ("x.bin", b"not audio at all", "application/octet-stream")})
        j = show("voice-prompt garbage", r)
        check(r.status_code == 415, "garbage audio -> 415")

        # ---------------- 4. translate
        r = c.post("/v1/extras/translate", json={"text": "Dadi's smile lit up our Diwali", "target": "hi-IN"})
        j = show("translate en->hi", r)
        check(r.status_code == 200 and j["text"], f"translate: {j.get('text')}")

    # ---------------- 5. fallback path, live: saaras + 105b (dictate skipped)
    import asyncio
    from memories.dictate import _llm_intent, keyterms
    from memories.extras_common import Timings
    from memories.sarvam import SarvamClient

    async def fb():
        cl = SarvamClient()
        try:
            t = Timings()
            with t.span("stt_saaras"):
                tr = await cl.transcribe(wav, "audio/wav", "p.wav", language_code="hi-IN", keyterms=keyterms(["Pihu"]))
            it = await _llm_intent(cl, tr["transcript"], ["Pihu"], t)
            return tr["transcript"], it, t.total()
        finally:
            await cl.aclose()
    tr, it, tm = asyncio.run(fb())
    print(f"\n== fallback saaras:v4 + sarvam-105b  timings_ms={tm}\n   transcript: {tr}\n   intent: "
          + json.dumps(it, ensure_ascii=False))
    check(it["destination"] == "status", "fallback destination status")
    check(any("Dadi" == p for p in it["people"]) or it["people"], f"fallback people {it['people']}")

    print(f"\nartifacts in {out_dir}")
    print("\nRESULT:", "PASS" if not FAILS else f"FAIL ({len(FAILS)}): {FAILS}")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
