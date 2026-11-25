"""Sarvam AI client: retries/backoff, 402 vs 429 handling, per-model rate limiting.

All calls are async (httpx). Every call is timed and recorded in the request trace.
"""
from __future__ import annotations

import asyncio
import base64
import json
import logging
import random
import re
import time
from collections import deque
from typing import Any

import httpx

from .config import get_settings
from .timing import record_call

log = logging.getLogger("memories.sarvam")


class SarvamError(Exception):
    pass


class SarvamQuotaError(SarvamError):
    """402: credits exhausted. Never retried."""


class SarvamAuthError(SarvamError):
    """403: bad key."""


class RateLimiter:
    """Sliding-window limiter: at most `per_min` requests started in any 60 s window."""

    def __init__(self, per_min: int):
        self.per_min = per_min
        self.starts: deque[float] = deque()
        self.lock = asyncio.Lock()

    async def acquire(self) -> None:
        async with self.lock:
            while True:
                now = time.monotonic()
                while self.starts and now - self.starts[0] > 60:
                    self.starts.popleft()
                if len(self.starts) < self.per_min:
                    self.starts.append(now)
                    return
                await asyncio.sleep(60 - (now - self.starts[0]) + 0.05)


LIMITS = {"gemma4": 50, "sarvam-105b": 60, "glm5.3-flash": 50, "stt": 60, "tts": 60, "translate": 60}

ACTIVITIES = ["team_working_at_laptops", "coding_closeup", "team_group_pose", "selfie", "stage_talk", "audience",
              "booth_or_sponsor", "organizer_or_staff", "judges_or_organizers", "venue_or_corridor", "swag_or_object", "food",
              "family_group", "ritual", "decor", "other"]
ANALYSIS_VERSION = 2

IMAGE_SCHEMA = {
    "type": "object",
    "properties": {
        "images": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "index": {"type": "integer"},
                    "caption": {"type": "string"},
                    "scene": {"type": "string"},
                    "people_count": {"type": "integer"},
                    "is_group": {"type": "boolean"},
                    "mood": {"type": "string"},
                    "quality": {"type": "integer"},
                    "blurry": {"type": "boolean"},
                    "subject_center": {"type": "array", "items": {"type": "number"}},
                    "moment_tag": {"type": "string"},
                    "best_window": {"type": "array", "items": {"type": "number"}},
                    "activity": {"type": "string", "enum": ACTIVITIES},
                    "team_work": {"type": "boolean"},
                    "candid": {"type": "boolean"},
                    "main_subjects": {"type": "string"},
                },
                "required": ["index", "caption", "scene", "people_count", "is_group", "mood",
                             "quality", "blurry", "subject_center", "moment_tag", "best_window",
                             "activity", "team_work", "candid", "main_subjects"],
            },
        }
    },
    "required": ["images"],
    "additionalProperties": False,
}

VISION_PROMPT = """You are a photo editor's assistant for family event albums (Indian festivals, weddings, events).
You get {n} images, numbered 0 to {last} in order. Some images are VIDEO CONTACT SHEETS: a 2x2 grid of 4 frames from one video, each labelled with its timestamp in seconds (marked below); judge them as one shot.
{notes}
For EACH image return an object with:
- index: the image number
- caption: one short, warm, specific sentence (max 12 words), English
- scene: 1-3 words (e.g. "rangoli", "aarti", "dinner table", "fireworks", "stage")
- people_count: number of visible people
- is_group: true if 3+ people pose or appear together
- mood: one of joyful, emotional, calm, festive, candid, funny, formal
- quality: 1-10 for how post-worthy it is (sharpness, light, composition, expressions)
- blurry: true if motion-blurred or out of focus
- subject_center: [x, y] of the main subject, each 0..1 relative to the image (for a contact sheet: relative to one frame)
- moment_tag: short tag for the moment (e.g. "lighting diyas", "group photo", "sweets", "phuljhadi")
- best_window: for a contact sheet, [start_s, end_s] of the most post-worthy 2-5 s using the frame timestamps; for a photo [0, 0]
- activity: exactly one of team_working_at_laptops (a few people building/discussing together at laptops, a table or whiteboard), coding_closeup (hands/screen/one person coding), team_group_pose (people posing together for the camera), selfie, stage_talk (speaker/panel on stage), audience (seated crowd watching), booth_or_sponsor (company booth, sponsor stand, people visiting it), organizer_or_staff (volunteers, staff, organisers, registration desk), venue_or_corridor (hall, aisle, corridor, entrance, people walking, building), swag_or_object (merch, robot, mascot, screens, objects), food, family_group, ritual, decor, other
- team_work: true only if people are actively building or discussing TOGETHER (laptops, whiteboard, a shared screen)
- candid: true if unposed
- main_subjects: 2-6 words naming who/what is the subject (e.g. "three teammates at laptops", "speaker on stage", "strangers walking")
Return JSON only: {{"images": [ ... ]}} with exactly {n} objects."""


def parse_json_tolerant(text: str) -> Any:
    """Parse JSON from model output: strips code fences / think blocks, finds the outermost object."""
    if text is None:
        raise ValueError("empty")
    t = text.strip()
    t = re.sub(r"<think>.*?</think>", "", t, flags=re.S).strip()
    t = re.sub(r"^```(?:json)?\s*|\s*```$", "", t, flags=re.S).strip()
    try:
        return json.loads(t)
    except Exception:
        pass
    for open_c, close_c in (("{", "}"), ("[", "]")):
        s = t.find(open_c)
        e = t.rfind(close_c)
        if s != -1 and e > s:
            chunk = t[s : e + 1]
            try:
                return json.loads(chunk)
            except Exception:
                # trailing commas
                try:
                    return json.loads(re.sub(r",\s*([}\]])", r"\1", chunk))
                except Exception:
                    continue
    raise ValueError("could not parse JSON from model output")


class SarvamClient:
    def __init__(self, api_key: str | None = None, base_url: str | None = None):
        s = get_settings()
        self.api_key = api_key if api_key is not None else s.sarvam_api_key
        self.base_url = (base_url or s.sarvam_base_url).rstrip("/")
        self.http = httpx.AsyncClient(timeout=httpx.Timeout(120, connect=15))
        self.limiters: dict[str, RateLimiter] = {}
        self._vision_format = "json_schema"  # downgraded on 400

    def limiter(self, key: str) -> RateLimiter:
        if key not in self.limiters:
            self.limiters[key] = RateLimiter(LIMITS.get(key, 60))
        return self.limiters[key]

    async def aclose(self) -> None:
        await self.http.aclose()

    async def _request(self, method: str, path: str, *, limit_key: str, kind: str, model: str,
                       retries: int = 4, **kw) -> httpx.Response:
        if not self.api_key:
            raise SarvamAuthError("SARVAM_API_KEY not set")
        headers = kw.pop("headers", {})
        headers["api-subscription-key"] = self.api_key
        last_err: Exception | None = None
        for attempt in range(retries + 1):
            await self.limiter(limit_key).acquire()
            t0 = time.perf_counter()
            try:
                r = await self.http.request(method, self.base_url + path, headers=headers, **kw)
            except (httpx.TransportError, httpx.TimeoutException) as e:
                record_call(kind, model, (time.perf_counter() - t0) * 1000, False, error=type(e).__name__, attempt=attempt)
                last_err = e
                await asyncio.sleep(min(20, 1.5 * 2**attempt) + random.random())
                continue
            ms = (time.perf_counter() - t0) * 1000
            if r.status_code < 400:
                record_call(kind, model, ms, True, attempt=attempt)
                return r
            body = r.text[:300]
            record_call(kind, model, ms, False, status=r.status_code, attempt=attempt)
            if r.status_code == 402:
                raise SarvamQuotaError(f"Sarvam credits exhausted (402): {body}")
            if r.status_code in (401, 403):
                raise SarvamAuthError(f"Sarvam auth failed ({r.status_code})")
            if r.status_code == 429 or r.status_code >= 500:
                ra = r.headers.get("retry-after")
                delay = float(ra) if ra and ra.replace(".", "").isdigit() else min(30, 2 * 2**attempt)
                log.warning("sarvam %s %s -> %s, retry in %.1fs", kind, model, r.status_code, delay)
                last_err = SarvamError(f"{r.status_code}: {body}")
                await asyncio.sleep(delay + random.random())
                continue
            raise SarvamError(f"{r.status_code}: {body}")
        raise SarvamError(f"retries exhausted: {last_err}")

    # ---------------- chat -----------------
    async def chat(self, model: str, messages: list[dict], *, v2: bool = False, kind: str = "chat",
                   **params) -> dict:
        path = "/v2/chat/completions" if v2 else "/v1/chat/completions"
        payload = {"model": model, "messages": messages, **{k: v for k, v in params.items()}}
        r = await self._request("POST", path, json=payload, limit_key=model, kind=kind, model=model)
        return r.json()

    @staticmethod
    def content_of(resp: dict) -> str:
        msg = (resp.get("choices") or [{}])[0].get("message") or {}
        return (msg.get("content") or "").strip()

    # ---------------- vision -----------------
    async def analyse_images(self, images: list[bytes], notes: list[str] | None = None,
                             model: str | None = None) -> list[dict]:
        """Analyse up to 6 JPEGs in one gemma4 call. Returns one dict per input image (in order)."""
        model = model or get_settings().vision_model
        n = len(images)
        note_txt = "\n".join(f"- image {i}: {t}" for i, t in enumerate(notes or []) if t)
        prompt = VISION_PROMPT.format(n=n, last=n - 1, notes=note_txt)
        content: list[dict] = [{"type": "text", "text": prompt}]
        for i, b in enumerate(images):
            content.append({"type": "text", "text": f"Image {i}:"})
            content.append({"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + base64.b64encode(b).decode()}})
        messages = [{"role": "user", "content": content}]
        formats = ["json_schema", "json_object", None]
        start = formats.index(self._vision_format) if self._vision_format in formats else 0
        last: Exception | None = None
        for fmt in formats[start:]:
            params: dict[str, Any] = {"temperature": 0.2, "max_tokens": 300 * n + 200}
            if fmt == "json_schema":
                params["response_format"] = {"type": "json_schema", "json_schema": {"name": "shots", "strict": True, "schema": IMAGE_SCHEMA}}
            elif fmt == "json_object":
                params["response_format"] = {"type": "json_object"}
            try:
                resp = await self.chat(model, messages, v2=True, kind="vision", **params)
            except SarvamError as e:
                if str(e).startswith("400") and fmt is not None:
                    log.warning("vision format %s rejected, downgrading", fmt)
                    self._vision_format = formats[formats.index(fmt) + 1]
                    last = e
                    continue
                raise
            try:
                data = parse_json_tolerant(self.content_of(resp))
            except ValueError as e:
                last = e
                continue
            items = data.get("images") if isinstance(data, dict) else data
            if not isinstance(items, list):
                last = ValueError("no images list")
                continue
            return normalise_shots(items, n)
        raise SarvamError(f"vision analysis failed: {last}")

    # ---------------- director -----------------
    async def plan_edit(self, system: str, user: str, *, model: str | None = None,
                        max_tokens: int = 4000) -> tuple[Any, str]:
        """Single-shot EDL request. Returns (parsed_json, raw_text)."""
        model = model or get_settings().director_model
        resp = await self.chat(
            model,
            [{"role": "system", "content": system}, {"role": "user", "content": user}],
            # reasoning off: with "low" the model spent the whole budget reasoning (finish_reason=length, empty content)
            kind="plan", reasoning_effort=None, temperature=0.4, max_tokens=max_tokens,
            response_format={"type": "json_object"},
        )
        raw = self.content_of(resp)
        return parse_json_tolerant(raw), raw

    # ---------------- speech / text -----------------
    async def transcribe(self, audio: bytes, content_type: str = "audio/wav", filename: str = "audio.wav",
                         language_code: str | None = None, keyterms: list[str] | None = None) -> dict:
        ct = (content_type or "audio/wav").split(";")[0].strip()
        data = {"model": "saaras:v4", "mode": "transcribe"}
        if language_code:
            data["language_code"] = language_code
        if keyterms:
            data["keyterms"] = json.dumps(keyterms[:50], ensure_ascii=False)
        r = await self._request("POST", "/speech-to-text", files={"file": (filename, audio, ct)}, data=data,
                                limit_key="stt", kind="stt", model="saaras:v4")
        return r.json()

    async def dictate(self, audio: bytes, content_type: str, filename: str, *, vocabulary: list[dict],
                      context: str, language_code: str = "hi-IN") -> dict:
        """POST /v2/dictate with vocabulary + context + output_rules -> transcript + JSON intent."""
        ct = (content_type or "audio/wav").split(";")[0].strip()
        rules = ("Return only one JSON object, no prose: {\"request\": <the request rewritten as one clear English "
                 "sentence>, \"people\": [names], \"include\": [moments/things wanted], \"exclude\": [things to "
                 "avoid], \"music\": <music wish or null>, \"destination\": <reel|status|story|null>, "
                 "\"mood\": <mood or null>}")
        data = {"language_code": language_code, "vocabulary": json.dumps(vocabulary, ensure_ascii=False),
                "context": json.dumps({"text": context}, ensure_ascii=False), "output_rules": rules}
        r = await self._request("POST", "/v2/dictate", files={"file": (filename, audio, ct)}, data=data,
                                limit_key="stt", kind="dictate", model="dictate")
        j = r.json()
        out = {"transcript": j.get("transcript", ""), "text": j.get("text", ""), "engine": "dictate",
               "corrections": j.get("corrections")}
        try:
            intent = parse_json_tolerant((j.get("output") or {}).get("text") or "")
            out["intent"] = intent
            if isinstance(intent, dict) and intent.get("request"):
                bits = [intent["request"]]
                if intent.get("people"):
                    bits.append("People: " + ", ".join(map(str, intent["people"])))
                if intent.get("exclude"):
                    bits.append("Avoid: " + ", ".join(map(str, intent["exclude"])))
                if intent.get("music"):
                    bits.append(f"Music: {intent['music']}")
                out["intent_text"] = ". ".join(bits) + f" (original words: {out['text'] or out['transcript']})"
        except Exception:
            pass
        return out

    async def doc_extract(self, data: bytes, content_type: str, filename: str, schema: dict,
                          language: str = "hi-IN", timeout_s: float = 60) -> dict:
        """Document AI extract job: submit, poll status, fetch results."""
        r = await self._request("POST", "/doc-ai/v1/job/extract",
                                files={"file": (filename, data, content_type or "image/jpeg")},
                                data={"schema": json.dumps(schema), "language": language, "output_format": "json", "mode": "basic"},
                                limit_key="docai", kind="docai_submit", model="doc-ai")
        job = r.json()["job_id"]
        t0 = time.monotonic()
        while time.monotonic() - t0 < timeout_s:
            await asyncio.sleep(2.5)
            st = (await self._request("GET", f"/doc-ai/v1/job/{job}/status", limit_key="docai", kind="docai_status", model="doc-ai")).json()
            status = st.get("status") or st.get("job_state")
            if status in ("completed", "partially_completed"):
                res = (await self._request("GET", f"/doc-ai/v1/job/{job}/results", limit_key="docai", kind="docai_results", model="doc-ai")).json()
                out = res.get("result", res)
                return out if isinstance(out, dict) else {"result": out}
            if status in ("failed", "rejected"):
                raise SarvamError(f"doc-ai job {status}")
        raise SarvamError("doc-ai job timed out")

    async def translate(self, text: str, target: str, source: str = "auto", mode: str = "modern-colloquial") -> str:
        if not text.strip():
            return text
        payload = {"input": text[:1000], "source_language_code": source, "target_language_code": target,
                   "model": "mayura:v1", "mode": mode}
        r = await self._request("POST", "/translate", json=payload, limit_key="translate", kind="translate", model="mayura:v1")
        return r.json().get("translated_text", text)

    async def tts(self, text: str, lang: str = "hi-IN", speaker: str = "simran_en_customer") -> bytes:
        payload = {"text": text[:2500], "language_code": lang, "model": "bulbul:v4-flash", "speaker": speaker}
        r = await self._request("POST", "/text-to-speech", json=payload, limit_key="tts", kind="tts", model="bulbul:v4-flash")
        return base64.b64decode("".join(r.json().get("audios", [])))


MOODS = {"joyful", "emotional", "calm", "festive", "candid", "funny", "formal"}


def normalise_shots(items: list, n: int) -> list[dict]:
    """Coerce model output into exactly n well-typed shot dicts (missing -> defaults)."""
    by_idx: dict[int, dict] = {}
    for pos, it in enumerate(items):
        if not isinstance(it, dict):
            continue
        idx = it.get("index", pos)
        try:
            idx = int(idx)
        except Exception:
            idx = pos
        if 0 <= idx < n and idx not in by_idx:
            by_idx[idx] = it
    out = []
    for i in range(n):
        it = by_idx.get(i, {})
        try:
            q = int(round(float(it.get("quality", 5))))
        except Exception:
            q = 5
        sc = it.get("subject_center") or [0.5, 0.5]
        try:
            sc = [min(1.0, max(0.0, float(sc[0]))), min(1.0, max(0.0, float(sc[1])))]
        except Exception:
            sc = [0.5, 0.5]
        try:
            pc = int(it.get("people_count", 0))
        except Exception:
            pc = 0
        mood = str(it.get("mood", "candid")).lower().strip()
        act = str(it.get("activity", "other")).lower().strip()
        out.append({
            "caption": str(it.get("caption", ""))[:160],
            "scene": str(it.get("scene", ""))[:40],
            "people_count": pc,
            "is_group": bool(it.get("is_group", pc >= 3)),
            "mood": mood if mood in MOODS else "candid",
            "quality": max(1, min(10, q)),
            "blurry": bool(it.get("blurry", False)),
            "subject_center": sc,
            "moment_tag": str(it.get("moment_tag", ""))[:40],
            "best_window": _window(it.get("best_window")),
            "activity": act if act in ACTIVITIES else "other",
            "team_work": bool(it.get("team_work", False)),
            "candid": bool(it.get("candid", True)),
            "main_subjects": str(it.get("main_subjects", ""))[:60],
            "v": ANALYSIS_VERSION,
            "ok": bool(it),
        })
    return out


def _window(w) -> list[float]:
    try:
        a, b = float(w[0]), float(w[1])
        return [a, b] if b > a >= 0 else [0.0, 0.0]
    except Exception:
        return [0.0, 0.0]
