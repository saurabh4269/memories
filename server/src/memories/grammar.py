"""Edit grammar enforcement (docs/EDIT-GRAMMAR.md) applied to every cut, whoever planned it.

shot value -> drop low-value shots -> trim videos to their best 1.5-3 s -> hook = best people shot ->
end on the best group/team shot held >= 2 s -> fit the destination length -> 3-5 short captions.
"""
from __future__ import annotations

import re
from typing import Any

from . import qa

POSITIVE_MOODS = {"joyful": 0.8, "funny": 0.8, "emotional": 0.8, "festive": 0.6, "candid": 0.4}
TEAM_RE = re.compile(r"team|group|friends|together|collaborat|huddle|selfie|posing|pose|celebrat|smil|laugh|cheer", re.I)
VIDEO_MIN_S, VIDEO_MAX_S = 1.5, 3.0
END_MIN_S, END_MAX_S = 2.0, 3.2

TOPICS: dict[str, tuple[str, str]] = {
    # request keyword regex -> shot text regex
    "stage": (r"stage|talk|keynote|speech|speaker|session|manch", r"stage|talk|keynote|speech|speak|present|audience|panel"),
    "team": (r"team|dost|friends|squad|saath|group", r"team|group|friends|collaborat|discussion|together|huddle|coding"),
    "fun": (r"fun|masti|energetic|hype|party|mazaa|mazedaar", r"fun|funny|joy|selfie|claw|game|goodies|swag|robot|mascot|laugh|crowd"),
    "code": (r"code|coding|hack|build|laptop", r"cod|laptop|workstation|screen|demo|build|hack"),
    "robot": (r"robot|mascot", r"robot|mascot"),
    "emotional": (r"emotion|yaad|dil|bhav|miss", r"group|friends|together|team|smil|joy|laugh"),
}

LABELS = {  # shot text regex -> (hinglish, english)
    r"stage|keynote|speech|speak|present|audience|panel": ("Stage pe jalwa", "Stage moments"),
    r"robot|mascot": ("Robot bhi aaya!", "Even the robot came"),
    r"goodies|swag|merch|sticker": ("Swag mil gaya", "Swag secured"),
    r"cod|laptop|workstation|screen|demo|build": ("Code, chai, repeat", "Code, coffee, repeat"),
    r"network|chat|conversation|booth|discussion": ("Nayi dosti, naye ideas", "New friends, new ideas"),
    r"crowd|hall|atmosphere|audience": ("Poora hall packed", "Packed hall energy"),
    r"selfie|fun|claw|game|laugh": ("Thodi masti bhi", "A little fun too"),
}
END_LABEL = ("Team ke saath", "Team for life")


def _an(r: dict) -> dict:
    return r.get("analysis") or {}


def _text(r: dict) -> str:
    an = _an(r)
    return f"{an.get('moment_tag') or ''} {an.get('caption') or ''} {an.get('scene') or ''}"


def topics_in(prompt: str) -> list[str]:
    return [k for k, (req, _) in TOPICS.items() if re.search(req, prompt or "", re.I)]


def topic_match(r: dict, topics: list[str]) -> bool:
    return any(re.search(TOPICS[t][1], _text(r), re.I) for t in topics)


def exclusive_topics(prompt: str) -> list[str]:
    """'sirf stage aur talks' / 'only stage': restrict the pool to the topic."""
    if re.search(r"\b(sirf|only|just|bas|keval)\b", prompt or "", re.I):
        return [t for t in topics_in(prompt) if t not in ("emotional",)]
    return []


BUILD_RE = re.compile(r"build|building|coding|code|laptop|hacking|keyboard|kaam karte", re.I)
CAPTION_RE = re.compile(r"caption|subtitle|text|title|likh|label|words on", re.I)
BUILD_ACTIVITIES = {"team_working_at_laptops", "coding_closeup"}


def wants_captions(prompt: str) -> bool:
    """Captions are OFF unless the user asks for them (user feedback 2026-11-25)."""
    return bool(CAPTION_RE.search(prompt or "")) and not re.search(r"no (caption|text)|bina (caption|text)", prompt or "", re.I)


def parse_intent(prompt: str, people: list[str] | None = None) -> dict:
    """Structured intent from the request: subject (team/stage/family/fun/None), topics, exclusive flag, names."""
    p = prompt or ""
    topics = topics_in(p)
    subject = None
    if re.search(r"recap|highlight|poora din|pura din|whole day|summary|best of|the day", p, re.I):
        subject = "recap"
    elif re.search(TOPICS["team"][0] + r"|building|hacking|my people|apne log", p, re.I):
        subject = "team"
    elif re.search(r"family|parivaar|ghar|nani|dadi|mummy|papa", p, re.I):
        subject = "family"
    elif "stage" in topics:
        subject = "stage"
    names = [n for n in (people or []) if n and re.search(r"\b" + re.escape(n) + r"\b", p, re.I)]
    excl = exclusive_topics(p)
    exclude = []
    for m in re.finditer(r"(?:no|without|bina|nahi)\s+(\w+)", p, re.I):
        exclude.append(m.group(1).lower())
    building = bool(BUILD_RE.search(p))
    return {"subject": subject, "topics": topics, "exclusive": excl, "people": names, "exclude": exclude,
            "building": building, "captions": wants_captions(p)}


STORY_ACTIVITIES = {"stage_talk", "swag_or_object", "food"}  # allowed in a team cut, <= 30% of clips


def team_ok(r: dict) -> bool:
    from .team import TEAM_THRESHOLD
    return float(r.get("team_score") or 0) >= TEAM_THRESHOLD and not r.get("judges")


CLAIMS = {  # words in a title/caption -> the clips must support them
    "team": (r"\b(team|squad|dost|friends|teammates|crew)\b", lambda r: team_ok(r) or bool(_an(r).get("is_group"))),
    "stage": (r"\b(stage|talk|keynote|speech|manch)\b", lambda r: _an(r).get("activity") in ("stage_talk", "audience")
              or bool(re.search(TOPICS["stage"][1], _text(r), re.I))),
    "robot": (r"\b(robot|mascot)\b", lambda r: bool(re.search(r"robot|mascot", _text(r), re.I))),
    "code": (r"\b(code|coding|hack|build)", lambda r: _an(r).get("activity") in ("team_working_at_laptops", "coding_closeup")
             or bool(re.search(TOPICS["code"][1], _text(r), re.I))),
}


def claim_share(text: str, rows: list[dict]) -> dict[str, float]:
    """For each claim the text makes, the share of rows that support it."""
    out = {}
    for k, (rx, ok) in CLAIMS.items():
        if re.search(rx, text or "", re.I):
            out[k] = sum(1 for r in rows if ok(r)) / max(1, len(rows))
    return out


def check_title(title: str, rows: list[dict], language: str, album_name: str = "") -> tuple[str, list[str]]:
    """A title must match its clips (team claims need >= 70% support, others >= 40%); else retitle."""
    bad = [k for k, v in claim_share(title, rows).items() if v < (0.7 if k == "team" else 0.4)]
    cleaned = short_caption(title, 5, 30)
    if cleaned != title.strip() and len(cleaned.split()) < 2:
        bad.append("mixed-script")
    if not bad:
        return cleaned or title, []
    hing = language in ("hinglish", "hi")
    fallback = (album_name and short_caption(album_name, 4, 26)) or ("Hackathon ki yaadein" if hing else "Hackathon memories")
    return fallback, [f"title {title!r} retitled: claim(s) {bad} not supported by the clips"]


def caption_ok(text: str, r: dict) -> bool:
    return all(v >= 1.0 for v in claim_share(text, [r]).values())


def meta(r: dict) -> dict:
    an = _an(r)
    return {"people_count": int(an.get("people_count") or 0), "is_group": bool(an.get("is_group")),
            "quality": an.get("quality"), "moment_tag": an.get("moment_tag"), "mood": an.get("mood"),
            "caption": an.get("caption"), "scene": an.get("scene"), "activity": an.get("activity"),
            "team_score": r.get("team_score"), "team_faces": r.get("team_faces")}


def shot_value(r: dict, topics: list[str] | None = None, subject: str | None = None) -> float:
    """people_count / is_group / emotion / quality; empty, corridor and walking shots are penalised."""
    an = _an(r)
    if subject == "team":
        return round(_base_value(r, topics) + 0.8 * float(r.get("team_score") or 0), 2)
    return _base_value(r, topics)


def _base_value(r: dict, topics: list[str] | None = None) -> float:
    an = _an(r)
    pc = int(an.get("people_count") or 0)
    v = 0.6 * int(an.get("quality", 5))
    v += -2.5 if pc == 0 else min(pc, 6) * 0.4
    if an.get("is_group") and 2 <= pc <= 12:
        v += 1.5
    if pc >= 15:
        v -= 0.5  # anonymous crowd
    v += POSITIVE_MOODS.get(str(an.get("mood") or ""), 0.0)
    if qa.LOW_VALUE_RE.search(_text(r)):
        v -= 4.0
    if an.get("blurry"):
        v -= 5.0
    if an.get("dup_of"):
        v -= 1.0
    if topics and topic_match(r, topics):
        v += 2.5
    if topics and "stage" in topics and an.get("activity") == "stage_talk":
        v += 2.0  # the speaker beats another audience shot
    if r.get("type") == "VIDEO" and pc > 0:
        v += 1.0  # motion keeps retention (§4.7)
    fa = r.get("facet") or {}
    if fa.get("aggregate") is not None:
        agg = float(fa["aggregate"])
        agg = agg * 10 if agg <= 1.0 else agg
        v = 0.6 * v + 0.4 * agg * 1.2
    return round(v, 2)


def end_value(r: dict, topics: list[str] | None = None) -> float:
    an = _an(r)
    pc = int(an.get("people_count") or 0)
    v = 3.0 * bool(an.get("is_group")) + 0.5 * int(an.get("quality", 5))
    v += 1.5 if 3 <= pc <= 10 else (0.5 if 2 <= pc <= 14 else -2.0)
    v += 2.0 if TEAM_RE.search(_text(r)) else 0.0
    v += POSITIVE_MOODS.get(str(an.get("mood") or ""), 0.0)
    if qa.LOW_VALUE_RE.search(_text(r)):
        v -= 4.0
    if topics and topic_match(r, topics):
        v += 1.0
    v += 0.8 * float(r.get("team_score") or 0)
    if an.get("activity") == "team_group_pose" or an.get("activity") == "selfie":
        v += 2.0
    return round(v, 2)


def video_window(r: dict, length: float) -> tuple[float, float]:
    """Best-window-centred [in, out] of `length` seconds inside the clip."""
    dur = float(r.get("duration") or 0)
    bw = _an(r).get("best_window") or [0, 0]
    if bw[1] > bw[0]:
        centre = (bw[0] + bw[1]) / 2
    else:
        centre = min(dur / 2, 2.0)
    length = min(length, dur)
    st = max(0.0, min(centre - length / 2, dur - length))
    return round(st, 3), round(st + length, 3)


DEVA = re.compile("[\u0900-\u097F]")


def clean_script(text: str) -> str:
    """Never mix scripts in one line (EDIT-GRAMMAR 9.7): keep the majority script's words."""
    t = str(text or "")
    if DEVA.search(t) and re.search(r"[A-Za-z]", t):
        latin = [w for w in t.split() if not DEVA.search(w)]
        deva = [w for w in t.split() if not re.search(r"[A-Za-z]", w)]
        return " ".join(latin if len(latin) >= len(deva) else deva)
    return t


def short_caption(text: str, max_words: int = 5, max_chars: int = 28) -> str:
    t = re.sub(r"[\U0001F300-\U0001FAFF\u2600-\u27BF]", "", clean_script(text)).strip(" ,!-")
    words = t.split()
    cut = False
    while words and (len(words) > max_words or len(" ".join(words)) > max_chars):
        words = words[:-1]
        cut = True
    while cut and words and words[-1].lower() in {"the", "on", "of", "ki", "ke", "ka", "aur", "and", "in", "at", "a", "se", "with", "for", "to"}:
        words = words[:-1]
    return " ".join(words)


def auto_label(r: dict, language: str, end: bool = False) -> str:
    i = 0 if language in ("hinglish", "hi") else 1
    if end:
        return END_LABEL[i]
    for rx, pair in LABELS.items():
        if re.search(rx, _text(r), re.I):
            return pair[i]
    return ""


def enforce(clips: list[dict], by_id: dict[str, dict], pool: list[dict], *, destination: str, prompt: str,
            language: str, beat: float, make_clip, snap, title: str = "", fast: bool = False,
            notes: list[str] | None = None, album_name: str = "", retitled: list[str] | None = None) -> list[dict]:
    """Return a grammar-conformant clip list. make_clip/snap come from director (avoids an import cycle)."""
    notes = notes if notes is not None else []
    retitled = retitled if retitled is not None else []
    lo, hi, target = qa.length_window(destination, prompt)
    intent = parse_intent(prompt)
    topics = intent["topics"]
    excl = intent["exclusive"]
    subject = intent["subject"]
    near = lambda a, b: _near(a, b)  # noqa: E731
    from .team import NOT_TEAM_ACTIVITIES
    n_team_pool = sum(1 for r in pool if team_ok(r))
    team_mode = subject == "team" and n_team_pool >= 4
    build_mode = intent["building"] and subject != "recap" and \
        sum(1 for r in pool if _an(r).get("activity") in BUILD_ACTIVITIES) >= 5
    if team_mode:
        notes.append(f"grammar: team intent, {n_team_pool} team shots available")

    def allowed(r: dict) -> bool:
        if excl and not topic_match(r, excl):
            return False
        if team_mode and not team_ok(r) and _an(r).get("activity") not in STORY_ACTIVITIES:
            return False
        if build_mode and (_an(r).get("activity") not in BUILD_ACTIVITIES or r.get("judges")):
            return False
        if subject in ("team", "family") and _an(r).get("activity") in NOT_TEAM_ACTIVITIES - {"audience"}:
            return False
        if any(x in _text(r).lower() for x in intent["exclude"]):
            return False
        return True

    # 1. unique sources, no near-duplicates, drop low-value shots (if we can afford to)
    kept: list[dict] = []
    for c in clips:
        r = by_id.get(c["asset_id"])
        if r is None or any(k["asset_id"] == c["asset_id"] for k in kept):
            continue
        if any(near(r, by_id[k["asset_id"]]) for k in kept):
            notes.append(f"grammar: dropped near-duplicate {r.get('alias', r['id'][:8])}")
            continue
        kept.append(c)
    candidates = sorted((r for r in pool if allowed(r)), key=lambda r: -shot_value(r, topics, subject))
    good_pool = [r for r in candidates if shot_value(r, topics, subject) >= 4.5 and not qa.LOW_VALUE_RE.search(_text(r))]
    if len(good_pool) < 6:
        good_pool = [r for r in candidates if shot_value(r, topics, subject) >= 2.5]
    filtered = [c for c in kept if allowed(by_id[c["asset_id"]])
                and shot_value(by_id[c["asset_id"]], topics, subject) >= 4.0
                and not qa.LOW_VALUE_RE.search(_text(by_id[c["asset_id"]]))]
    if len(filtered) + len(good_pool) >= 6 or team_mode or excl:
        dropped = len(kept) - len(filtered)
        if dropped:
            notes.append(f"grammar: dropped {dropped} low-value/off-topic shot(s)")
        kept = filtered

    # 2. durations: videos = best 1.5-3 s window; photos by energy
    photo_hold = 1.4 if fast else 2.0
    vid_len = 1.9 if fast else 2.6

    def shape(c: dict) -> dict:
        r = by_id[c["asset_id"]]
        if c["kind"] == "video":
            L = snap(vid_len, beat, VIDEO_MIN_S, VIDEO_MAX_S)
            st, en = video_window(r, L)
            if en - st < VIDEO_MIN_S - 1e-6:
                return {}
            c.update(in_s=st, out_s=en, max_len=round(float(r.get("duration") or en) - st, 3))
        else:
            c["hold_s"] = snap(photo_hold, beat, 1.0, 3.0)
        return c

    def new_clip(r: dict) -> dict | None:
        c = make_clip(r, beat, hold_s=photo_hold, out_s=3.0)
        return (shape(c) or None) if c else None

    kept = [x for x in (shape(c) for c in kept) if x]

    def used_rows() -> list[dict]:
        return [by_id[c["asset_id"]] for c in kept]

    def fits(r: dict, exclude: str | None = None) -> bool:
        ids = {c["asset_id"] for c in kept}
        return r["id"] not in ids and not any(near(r, u) for u in used_rows() if u["id"] != exclude)

    # 3. ending: best group/team shot, held >= 2 s
    end_cands = [r for r in {c["asset_id"]: by_id[c["asset_id"]] for c in kept}.values()] + \
                [r for r in good_pool if fits(r)]
    end_cands = [r for r in end_cands if _an(r).get("is_group") or int(_an(r).get("people_count") or 0) >= 2] or end_cands
    end_clip = None
    if end_cands:
        best_end = max(end_cands, key=lambda r: (end_value(r, topics), r["type"] == "IMAGE"))
        end_clip = next((c for c in kept if c["asset_id"] == best_end["id"]), None) or new_clip(best_end)
        kept = [c for c in kept if c["asset_id"] != best_end["id"]]

    # 4. hook: the highest-value people shot
    hook_pool = [c for c in kept if int(_an(by_id[c["asset_id"]]).get("people_count") or 0) > 0] or kept
    hook = max(hook_pool, key=lambda c: (shot_value(by_id[c["asset_id"]], topics, subject),
                                         c["kind"] == "video")) if hook_pool else None
    if hook is None:
        cand = next((r for r in good_pool if fits(r) and (end_clip is None or r["id"] != end_clip["asset_id"])), None)
        hook = new_clip(cand) if cand else None
    middle = [c for c in kept if hook is None or c["asset_id"] != hook["asset_id"]]

    def total() -> float:
        return sum(qa.clip_len(c) for c in ([hook] if hook else []) + middle + ([end_clip] if end_clip else []))

    if hook:
        hook_len = 1.5
        if hook["kind"] == "video":
            st, en = video_window(by_id[hook["asset_id"]], snap(hook_len, beat, 1.2, 1.6))
            hook.update(in_s=st, out_s=en)
        else:
            hook["hold_s"] = snap(hook_len, beat, 1.2, 1.6)
    if end_clip:
        if end_clip["kind"] == "video":
            r = by_id[end_clip["asset_id"]]
            st, en = video_window(r, snap(2.6, beat, END_MIN_S, END_MAX_S))
            end_clip.update(in_s=st, out_s=en)
        else:
            end_clip["hold_s"] = snap(2.6 if not fast else 2.2, beat, END_MIN_S, END_MAX_S)

    # 5. fit length: drop lowest-value middle shots when long, add best unused shots when short
    while total() > hi + 1e-6 and len(middle) > 2:
        worst = min(range(len(middle)), key=lambda i: shot_value(by_id[middle[i]["asset_id"]], topics, subject))
        middle.pop(worst)
    taken = {c["asset_id"] for c in ([hook] if hook else []) + middle + ([end_clip] if end_clip else [])}
    for r in good_pool + [r for r in candidates if r not in good_pool and shot_value(r, topics, subject) >= 3.0]:
        if total() >= target - 0.3:
            break
        if r["id"] in taken or any(near(r, by_id[t]) for t in taken):
            continue
        c = new_clip(r)
        if c is None:
            continue
        if total() + qa.clip_len(c) > hi + 1e-6:
            continue
        middle.append(c)
        taken.add(r["id"])
    # still short (small album): stretch photos a beat at a time, up to 3 s
    for _ in range(20):
        if total() >= lo - 1e-6:
            break
        grew = False
        for c in middle:
            if c["kind"] == "photo" and c["hold_s"] + beat <= 3.0 + 1e-6 and total() + beat <= hi:
                c["hold_s"] = round(c["hold_s"] + beat, 3)
                grew = True
                if total() >= lo:
                    break
        if not grew:
            break
    while total() > hi + 1e-6 and middle:
        longest = max(middle, key=qa.clip_len)
        if longest["kind"] == "photo" and longest["hold_s"] - beat >= 1.0:
            longest["hold_s"] = round(longest["hold_s"] - beat, 3)
        else:
            middle.remove(longest)

    # video share >= 30% when good motion exists (§4.7): swap the weakest photos for the best unused videos
    vids = [r for r in candidates if r["type"] == "VIDEO" and shot_value(r, topics, subject) >= 4.0
            and int(_an(r).get("people_count") or 0) > 0 and not qa.LOW_VALUE_RE.search(_text(r))
            and (not team_mode or team_ok(r) or _an(r).get("activity") == "stage_talk")]
    vids.sort(key=lambda r: (not team_ok(r), -shot_value(r, topics, subject)))
    taken = {c["asset_id"] for c in ([hook] if hook else []) + middle + ([end_clip] if end_clip else [])}
    for r in vids:
        if total() <= 0 or sum(qa.clip_len(c) for c in ([hook] if hook else []) + middle + ([end_clip] if end_clip else [])
                              if c["kind"] == "video") / total() >= 0.3:
            break
        if r["id"] in taken or any(near(r, by_id[t]) for t in taken):
            continue
        c = new_clip(r)
        if not c:
            continue
        photos = [m for m in middle if m["kind"] == "photo"]
        while photos and total() + qa.clip_len(c) > hi + 1e-6:
            weakest = min(photos, key=lambda m: shot_value(by_id[m["asset_id"]], topics, subject))
            middle.remove(weakest)
            photos.remove(weakest)
        if total() + qa.clip_len(c) <= hi + 1e-6:
            middle.append(c)
            taken.add(r["id"])
    if team_mode:  # >= 70% of clips must be the team (story shots fill the rest)
        allc = ([hook] if hook else []) + middle + ([end_clip] if end_clip else [])
        cap = int(0.3 * len(allc))
        non = sorted([c for c in middle if not team_ok(by_id[c["asset_id"]])],
                     key=lambda c: shot_value(by_id[c["asset_id"]], topics, subject))
        while len(non) > cap:
            middle.remove(non.pop(0))
    # 6. order: the day's story (chronological), no 3 same-activity shots in a row
    middle.sort(key=lambda c: by_id[c["asset_id"]].get("time") or "")
    act = lambda c: _an(by_id[c["asset_id"]]).get("activity") or (_an(by_id[c["asset_id"]]).get("moment_tag") or "")  # noqa: E731
    for i in range(2, len(middle)):
        if act(middle[i]) == act(middle[i - 1]) == act(middle[i - 2]):
            j = next((j for j in range(i + 1, len(middle)) if act(middle[j]) != act(middle[i])), None)
            if j is not None:
                middle.insert(i, middle.pop(j))
    for i in range(1, len(middle)):
        a, b = by_id[middle[i - 1]["asset_id"]], by_id[middle[i]["asset_id"]]
        if (_an(a).get("moment_tag") or "x") == (_an(b).get("moment_tag") or "y") and i + 1 < len(middle):
            middle[i], middle[i + 1] = middle[i + 1], middle[i]
    out = ([hook] if hook else []) + middle + ([end_clip] if end_clip and end_clip is not hook else [])
    if subject == "recap":
        out = recap_assemble(by_id, pool, destination, prompt, language, beat, new_clip, near, notes, fast) or out

    # 7. captions: title on the hook, 3-5 total, short; end line on the closing shot
    for c in out:
        c["caption"] = short_caption(c.get("caption", ""))
        if c["caption"] and not caption_ok(c["caption"], by_id[c["asset_id"]]):
            notes.append(f"grammar: dropped caption {c['caption']!r} (does not match its shot)")
            c["caption"] = ""
        c.pop("title_card", None)
    title, tn = check_title(title, [by_id[c["asset_id"]] for c in out], language, album_name)
    notes += tn
    if tn:
        retitled.append(title)
    if out:
        out[0]["caption"] = short_caption(title, 5, 30) or out[0]["caption"] or auto_label(by_id[out[0]["asset_id"]], language)
        out[0]["title_card"] = True
    if len(out) > 1 and (not out[-1]["caption"] or (subject == "team" and len(out[-1]["caption"].split()) <= 2)):
        out[-1]["caption"] = auto_label(by_id[out[-1]["asset_id"]], language,
                                        end=subject in ("team", "recap", None) and not excl)
    n_caps = lambda: sum(1 for c in out if c["caption"])  # noqa: E731
    used_labels = {c["caption"] for c in out if c["caption"]}
    for i, c in enumerate(out[1:-1], start=1):
        if n_caps() >= 4:
            break
        if c["caption"] or out[i - 1]["caption"]:
            continue
        lab = auto_label(by_id[c["asset_id"]], language)
        if lab and lab not in used_labels:
            c["caption"] = lab
            used_labels.add(lab)
    for c in reversed(out[1:-1]):
        if n_caps() <= 5:
            break
        c["caption"] = ""
    if not intent["captions"]:
        for c in out:
            c["caption"] = ""
        notes.append("grammar: captions off (not requested)")
    for c in out:
        c["meta"] = {**meta(by_id[c["asset_id"]]), "value": shot_value(by_id[c["asset_id"]], topics, subject)}
    return out


def _near(a: dict, b: dict) -> bool:
    """director.near_duplicate + 'same people, same place, same activity within 20 min' (no jump-cut repeats, §4.3)."""
    from .director import near_duplicate
    if near_duplicate(a, b):
        return True
    shared = set(a.get("person_ids") or []) & set(b.get("person_ids") or [])
    if len(shared) >= 2 and _an(a).get("activity") == _an(b).get("activity") and a["type"] == b["type"] == "IMAGE":
        try:
            from datetime import datetime
            ta = datetime.fromisoformat((a.get("time") or "").replace("Z", "+00:00"))
            tb = datetime.fromisoformat((b.get("time") or "").replace("Z", "+00:00"))
            return abs((ta - tb).total_seconds()) <= 1200
        except Exception:
            return False
    return False


def summary(clips: list[dict]) -> dict[str, Any]:
    return {"n": len(clips), "total": round(sum(qa.clip_len(c) for c in clips), 2)}


RECAP_LABELS = {  # slot -> (hinglish, english)
    "venue": ("Day 1. Bengaluru.", "Day 1. Bengaluru."),
    "build": ("Heads down, building.", "Heads down, building."),
    "stage": ("Demo time.", "Demo time."),
    "sponsor": ("Booths, swag, ideas.", "Booths, swag, ideas."),
    "robot": ("Robot bhi aaya!", "Even the robot showed up."),
    "end": ("Team ke saath.", "Built together."),
}


def recap_assemble(by_id: dict, pool: list[dict], destination: str, prompt: str, language: str, beat: float,
                   new_clip, near, notes: list[str], fast: bool) -> list[dict] | None:
    """Event recap (§5.4 conference/hackathon template): hook on the team -> 1 venue establishing shot ->
    team building -> stage / sponsor moments -> the robot -> more building -> end on the team."""
    lo, hi, target = qa.length_window(destination, prompt)
    rows = [r for r in pool if not _an(r).get("blurry")]
    act = lambda r: _an(r).get("activity") or ""  # noqa: E731
    val = lambda r: shot_value(r, [], None)  # noqa: E731
    used: list[dict] = []

    def best(pred, key=val, prefer_video=False) -> dict | None:
        c = [r for r in rows if pred(r) and r not in used and not any(near(r, u) for u in used)
             and (r["type"] != "VIDEO" or float(r.get("duration") or 0) >= 2.0)]
        if not c:
            return None
        return max(c, key=lambda r: (key(r) + (1.5 if prefer_video and r["type"] == "VIDEO" else 0)))

    team_key = lambda r: val(r) + 0.8 * float(r.get("team_score") or 0)  # noqa: E731
    slots: list[tuple[str, dict | None]] = []

    def take(slot: str, r: dict | None) -> None:
        if r is not None:
            used.append(r)
            slots.append((slot, r))

    end = best(lambda r: team_ok(r) and int(_an(r).get("people_count") or 0) >= 2,
               key=lambda r: end_value(r) + (2 if act(r) in ("team_group_pose", "selfie") else 0))
    if end is not None:
        used.append(end)
    take("hook", best(lambda r: team_ok(r) and int(_an(r).get("people_count") or 0) >= 2, key=team_key, prefer_video=True))
    take("venue", best(lambda r: act(r) in ("venue_or_corridor", "audience", "booth_or_sponsor", "other")
                       and bool(re.search(r"wide|hall|atmosphere|crowd|venue|exhibition", _text(r), re.I))
                       and int(_an(r).get("people_count") or 0) >= 6 and not re.search(r"walk", _text(r), re.I)
                       and r["type"] == "IMAGE", key=lambda r: int(_an(r).get("quality", 5)) + 0.05 * int(_an(r).get("people_count") or 0)))
    take("build", best(lambda r: team_ok(r), key=team_key, prefer_video=True))
    take("build", best(lambda r: team_ok(r) and act(r) == "coding_closeup", key=team_key))
    take("stage", best(lambda r: act(r) == "stage_talk", prefer_video=True))
    take("sponsor", best(lambda r: act(r) == "booth_or_sponsor" and int(_an(r).get("people_count") or 0) >= 2))
    take("robot", best(lambda r: bool(re.search(r"robot|mascot", _text(r), re.I)), key=lambda r: int(_an(r).get("quality", 5))))
    while True:
        r = best(lambda r: team_ok(r), key=team_key, prefer_video=True)
        if r is None:
            break
        take("build", r)
        if len(slots) >= 11:
            break
    if end is not None:
        slots.append(("end", end))
    if len(slots) < 5:
        return None
    clips: list[dict] = []
    for slot, r in slots:
        c = new_clip(r)
        if not c:
            continue
        if slot == "hook":
            if c["kind"] == "video":
                st, en = video_window(r, 1.5)
                c.update(in_s=st, out_s=en)
            else:
                c["hold_s"] = round(max(1, round(1.5 / beat)) * beat, 3)
        if slot == "end":
            if c["kind"] == "video":
                st, en = video_window(r, 2.6)
                c.update(in_s=st, out_s=en)
            else:
                c["hold_s"] = round(max(1, round(2.6 / beat)) * beat, 3)
        c["slot"] = slot
        clips.append(c)
    total = lambda: sum(qa.clip_len(c) for c in clips)  # noqa: E731
    while total() > hi + 1e-6:
        extra = [c for c in clips if c["slot"] == "build"]
        if len(extra) <= 2:
            break
        clips.remove(min(extra[2:] or extra, key=lambda c: team_key(by_id[c["asset_id"]])))
    # order: hook, venue, then the rest by time (story of the day), end last
    head = [c for c in clips if c["slot"] in ("hook", "venue")]
    head.sort(key=lambda c: c["slot"] != "hook")
    mid = sorted([c for c in clips if c["slot"] not in ("hook", "venue", "end")],
                 key=lambda c: by_id[c["asset_id"]].get("time") or "")
    tail = [c for c in clips if c["slot"] == "end"]
    out = head + mid + tail
    i = 0 if language in ("hinglish", "hi") else 1
    seen_slots: set[str] = set()
    for c in out:
        c["caption"] = ""
        if c["slot"] in RECAP_LABELS and c["slot"] not in seen_slots and c["slot"] in ("venue", "build", "stage", "robot", "end"):
            c["caption"] = RECAP_LABELS[c["slot"]][i]
            seen_slots.add(c["slot"])
    notes.append("grammar: recap template " + ",".join(c["slot"] for c in out))
    return out
