"""Who is "the team"? Recurring Immich face clusters + gemma4 activity + CLIP search -> team_score per asset.

Strangers (organisers, booth staff, people walking past) appear in one or two shots; the user's own team recurs
across many shots and co-occurs with team_working_at_laptops / team_group_pose shots. Immich only forms a person
cluster after several faces, so a cluster is already a weak "recurring" signal.
"""
from __future__ import annotations

import asyncio
import logging
import re
from collections import Counter

log = logging.getLogger("memories.team")

TEAM_ACTIVITIES = {"team_working_at_laptops", "coding_closeup", "team_group_pose", "selfie"}
NOT_TEAM_ACTIVITIES = {"booth_or_sponsor", "organizer_or_staff", "venue_or_corridor", "audience", "stage_talk",
                       "judges_or_organizers"}
JUDGE_ACTIVITIES = {"stage_talk", "organizer_or_staff", "judges_or_organizers"}
JUDGE_RE = re.compile(r"\bmic\b|microphone|speaker|judge|panel|host|organi[sz]er|on stage|volunteer|staff", re.I)
CLIP_QUERIES = ["people coding on laptops at a table", "team discussing around a laptop", "group selfie",
                "friends posing together for a group photo", "hackers working late at night on laptops"]
TEAM_THRESHOLD = 3.0
TEXT_TEAM_RE = re.compile(r"teammate|team|collaborat|coding together|discussing code|working on (their|laptops)|laptops", re.I)


def _an(r: dict) -> dict:
    return r.get("analysis") or {}


def is_judge(r: dict) -> bool:
    """Judges / organisers / speakers: stage or staff activity, or a mic/speaker in the description."""
    an = _an(r)
    if an.get("activity") in JUDGE_ACTIVITIES:
        return True
    text = f"{an.get('caption') or ''} {an.get('main_subjects') or ''} {an.get('moment_tag') or ''}"
    return bool(JUDGE_RE.search(text)) and an.get("activity") not in ("team_working_at_laptops", "coding_closeup")


def team_people(rows: list[dict], top: int = 10) -> list[str]:
    """Person ids that recur across the album, ranked by co-occurrence with team activity."""
    count: Counter = Counter()
    team_co: Counter = Counter()
    judge_co: Counter = Counter()
    for r in rows:
        ids = set(r.get("person_ids") or [])
        an = _an(r)
        is_team_shot = an.get("activity") in TEAM_ACTIVITIES or an.get("team_work")
        is_judge_shot = is_judge(r)
        for p in ids:
            count[p] += 1
            if is_team_shot and not is_judge_shot:
                team_co[p] += 1
            if is_judge_shot:
                judge_co[p] += 1
    any_team = any(team_co.values())
    ranked = sorted(count, key=lambda p: -(count[p] + 2 * team_co[p]))
    out = []
    for p in ranked:
        if count[p] < 3:
            continue
        if any_team and team_co[p] == 0:
            continue  # recurring but never seen building: probably staff / a booth person
        if judge_co[p] >= max(1, team_co[p]):
            continue  # judges / organisers: standing with a mic near the stage, not at laptops
        out.append(p)
    return out[:top]


def score_rows(rows: list[dict], clip_hits: dict[str, float] | None = None) -> list[str]:
    """Annotate rows with team_faces / team_score. Returns the team person ids."""
    team = set(team_people(rows))
    clip_hits = clip_hits or {}
    for r in rows:
        an = _an(r)
        faces = len(team & set(r.get("person_ids") or []))
        act = an.get("activity") or ""
        s = 1.5 * min(2, faces)
        s += 2.0 if an.get("team_work") else 0.0
        s += 2.0 if act in TEAM_ACTIVITIES else 0.0
        if not an.get("activity") and TEXT_TEAM_RE.search(f"{an.get('caption') or ''} {an.get('moment_tag') or ''}"):
            s += 1.5  # legacy analysis without activity
        s += clip_hits.get(r["id"], 0.0)
        if act in NOT_TEAM_ACTIVITIES or is_judge(r):
            s -= 3.0
        r["judges"] = is_judge(r)
        if int(an.get("people_count") or 0) == 0 and act not in ("coding_closeup",):
            s -= 2.0
        r["team_faces"] = faces
        r["team_score"] = round(s, 2)
    return sorted(team)


async def clip_signal(immich, album_id: str) -> dict[str, float]:
    """Immich smart search hits for team-ish queries: up to +1.5 for top ranks."""
    async def one(q: str):
        try:
            return await immich.smart_search(q, album_id, size=12)
        except Exception as e:
            log.debug("smart search failed for %r: %s", q, e)
            return []
    res = await asyncio.gather(*(one(q) for q in CLIP_QUERIES))
    hits: dict[str, float] = {}
    for items in res:
        for rank, a in enumerate(items):
            hits[a["id"]] = max(hits.get(a["id"], 0.0), 1.5 * (1 - rank / 12))
    return hits


async def annotate(immich, album_id: str, rows: list[dict]) -> dict:
    hits = await clip_signal(immich, album_id)
    team = score_rows(rows, hits)
    n_team = sum(1 for r in rows if r.get("team_score", 0) >= TEAM_THRESHOLD)
    return {"team_people": team, "team_assets": n_team, "clip_hits": len(hits)}
