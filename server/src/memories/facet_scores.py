"""Facet objective photo-quality signals for the director (read-only, cached per album).

Facet (github.com/ncoevoet/facet, MIT) runs as its own container on the VM and scores every
photo on aesthetic / composition / face quality / eye sharpness / technical sharpness /
colour / exposure / saliency / dynamic range, and detects blinks, bursts, near-duplicates,
similarity groups and chronological scenes, plus zero-shot narrative-moment labels and a
saliency subject box for social crops.

Pipeline:
    Facet DB --(scripts/facet_export.py, run inside the facet container)--> facet_raw.json
    facet_raw.json + Immich album assets --(refresh_scores)--> <data_dir>/facet/<album_id>.json
    load_scores(album_id) -> {asset_id: {...}}   (reads the per-album cache)

Only photos are scored (Facet does not score videos): video asset ids are absent from the
result, so callers must treat "missing" as "no signal", never as "bad".

CLI refresh:  python -m memories.facet_scores <album_id> [--raw PATH]
"""
from __future__ import annotations

import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

# Seconds of slack when matching a Facet capture time to an Immich one.
_TIME_SLACK_S = 120.0
_SCORE_KEYS = ("aggregate", "aesthetic", "composition", "face_quality", "eye_sharpness", "sharpness",
               "color", "exposure")


def facet_dir() -> Path:
    if os.environ.get("FACET_DIR"):
        d = Path(os.environ["FACET_DIR"])
    else:
        from memories.config import get_settings

        d = get_settings().data_dir / "facet"
    d.mkdir(parents=True, exist_ok=True)
    return d


def raw_path() -> Path:
    return Path(os.environ.get("FACET_RAW_PATH") or facet_dir() / "facet_raw.json")


def cache_path(album_id: str) -> Path:
    return facet_dir() / f"{album_id}.json"


# ---------------------------------------------------------------- helpers

def _f(v: Any) -> float | None:
    try:
        return None if v is None else round(float(v), 3)
    except (TypeError, ValueError):
        return None


def _parse_time(s: Any) -> datetime | None:
    """Facet stores EXIF 'YYYY:MM:DD HH:MM:SS' (local, naive); Immich ISO-8601."""
    if not s:
        return None
    s = str(s).strip()
    for fmt in ("%Y:%m:%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y:%m:%d %H:%M:%S.%f"):
        try:
            return datetime.strptime(s[:26], fmt)
        except ValueError:
            pass
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def _naive_local(dt: datetime | None) -> datetime | None:
    return dt.replace(tzinfo=None) if dt else None


def _bbox(v: Any) -> list[float] | None:
    if not v:
        return None
    try:
        b = json.loads(v) if isinstance(v, str) else v
        b = [float(x) for x in b][:4]
        return b if len(b) == 4 and b[2] > b[0] and b[3] > b[1] else None
    except (TypeError, ValueError):
        return None


def crop_box(subject_box: list[float] | None, width: int | None, height: int | None,
             aspect: float = 9 / 16) -> list[float] | None:
    """Normalised [x0,y0,x1,y1] crop of the given aspect (w/h) that contains as much of the
    subject box as fits, centred on it. None when the image size is unknown."""
    if not width or not height:
        return None
    sb = subject_box or [0.0, 0.0, 1.0, 1.0]
    cx, cy = (sb[0] + sb[2]) / 2, (sb[1] + sb[3]) / 2
    img_aspect = width / height
    if img_aspect >= aspect:  # crop width
        cw, ch = aspect / img_aspect, 1.0
    else:  # crop height
        cw, ch = 1.0, img_aspect / aspect
    x0 = min(max(cx - cw / 2, 0.0), 1.0 - cw)
    y0 = min(max(cy - ch / 2, 0.0), 1.0 - ch)
    return [round(x0, 4), round(y0, 4), round(x0 + cw, 4), round(y0 + ch, 4)]


# ---------------------------------------------------------------- matching

def match_assets(photos: dict[str, dict], assets: list[dict]) -> dict[str, str]:
    """Map Facet path -> Immich asset id by original filename, tie-broken by capture time."""
    by_name: dict[str, list[dict]] = {}
    for a in assets:
        if a.get("type", "IMAGE") != "IMAGE":
            continue
        name = (a.get("originalFileName") or "").lower()
        if name:
            by_name.setdefault(name, []).append(a)
    out: dict[str, str] = {}
    used: set[str] = set()
    # shallowest path first, so a top-level original wins over a copy in a subfolder
    for path, p in sorted(photos.items(), key=lambda kv: (kv[0].count("/"), kv[0])):
        name = (p.get("filename") or os.path.basename(path)).lower()
        cands = [a for a in by_name.get(name, []) if a["id"] not in used]
        if not cands:
            continue
        ft = _naive_local(_parse_time(p.get("date_taken")))
        if len(cands) > 1 and ft:
            def dist(a: dict) -> float:
                exif = a.get("exifInfo") or {}
                at = _parse_time(a.get("localDateTime") or exif.get("dateTimeOriginal") or a.get("fileCreatedAt"))
                return abs((_naive_local(at) - ft).total_seconds()) if at else 1e12
            cands.sort(key=dist)
            if dist(cands[0]) > _TIME_SLACK_S and dist(cands[0]) != 1e12:
                log.debug("facet: %s time mismatch with all candidates", name)
        out[path] = cands[0]["id"]
        used.add(cands[0]["id"])
    return out


# ---------------------------------------------------------------- build

def build_scores(raw: dict, assets: list[dict]) -> dict[str, dict]:
    photos: dict[str, dict] = raw.get("photos", {})
    path2id = match_assets(photos, assets)
    # Only matched photos count: the same file scanned twice (e.g. a copy in a subfolder)
    # must not make the album's copy a "non-lead" of its own unmatched twin.
    matched = {path: photos[path] for path in path2id}

    def _leads(group_key: str, lead_key: str) -> tuple[dict[Any, str], dict[Any, int]]:
        members: dict[Any, list[str]] = {}
        for path, p in matched.items():
            if p.get(group_key) is not None:
                members.setdefault(p[group_key], []).append(path)
        leads: dict[Any, str] = {}
        for g, paths in members.items():
            flagged = [x for x in paths if matched[x].get(lead_key)]
            best = flagged[0] if flagged else max(paths, key=lambda x: matched[x].get("aggregate") or 0)
            leads[g] = best
        return leads, {g: len(v) for g, v in members.items()}

    burst_lead, burst_sizes = _leads("burst_group_id", "is_burst_lead")
    dup_lead, dup_sizes = _leads("duplicate_group_id", "is_duplicate_lead")

    out: dict[str, dict] = {}
    for path, p in matched.items():
        aid = path2id[path]
        bg = p.get("burst_group_id")
        in_burst = bg is not None and burst_sizes.get(bg, 0) > 1
        dg = p.get("duplicate_group_id")
        dup_of = None
        if dg is not None and dup_sizes.get(dg, 0) > 1 and dup_lead[dg] != path:
            dup_of = path2id[dup_lead[dg]]
        sbox = _bbox(p.get("subject_bbox"))
        moment = p.get("narrative_moment")
        rec = {
            "filename": p.get("filename") or os.path.basename(path),
            "taken_at": p.get("date_taken"),
            "aggregate": _f(p.get("aggregate")),
            "aesthetic": _f(p.get("aesthetic")),
            "composition": _f(p.get("comp_score")),
            "composition_pattern": p.get("composition_pattern"),
            "face_count": int(p.get("face_count") or 0),
            "face_quality": _f(p.get("face_quality")),
            "eye_sharpness": _f(p.get("eye_sharpness")),
            "sharpness": _f(p.get("tech_sharpness")),
            "color": _f(p.get("color_score")),
            "exposure": _f(p.get("exposure_score")),
            "dynamic_range": _f(p.get("dynamic_range_stops")),
            "saliency": _f(p.get("subject_prominence")),
            "blink": bool(p.get("is_blink")),
            "burst_group": f"b{bg}" if in_burst else None,
            "is_burst_lead": (burst_lead[bg] == path) if in_burst else True,
            "duplicate_of": dup_of,
            "similarity_group": f"s{p['similarity_group']}" if p.get("similarity_group") is not None else None,
            "scene_id": p.get("scene_id"),
            "moment_labels": [moment] if moment and moment != "other" else [],
            "moment_confidence": _f(p.get("narrative_moment_confidence")),
            "category": p.get("category"),
            "tags": [t.strip() for t in (p.get("tags") or "").split(",") if t.strip()],
            "subject_box": sbox,
            "crop_9x16": crop_box(sbox, p.get("image_width"), p.get("image_height")),
            "width": p.get("image_width"),
            "height": p.get("image_height"),
        }
        reasons = []
        if rec["blink"]:
            reasons.append("blink")
        if not rec["is_burst_lead"]:
            reasons.append("burst_non_lead")
        if rec["duplicate_of"]:
            reasons.append("duplicate")
        if p.get("junk_kind") and p.get("junk_kind") != "not_junk":
            reasons.append(f"junk:{p['junk_kind']}")
        rec["cull"] = bool(reasons)
        rec["cull_reasons"] = reasons
        out[aid] = rec
    return out


def summarize(scores: dict[str, dict]) -> dict:
    aggs = sorted((v["aggregate"] for v in scores.values() if v.get("aggregate") is not None), reverse=True)
    ranked = sorted(scores.items(), key=lambda kv: kv[1].get("aggregate") or 0, reverse=True)
    moments: dict[str, int] = {}
    for v in scores.values():
        for m in v["moment_labels"]:
            moments[m] = moments.get(m, 0) + 1
    return {
        "scored": len(scores),
        "aggregate_mean": round(sum(aggs) / len(aggs), 3) if aggs else None,
        "aggregate_max": aggs[0] if aggs else None,
        "aggregate_min": aggs[-1] if aggs else None,
        "blinks": sum(v["blink"] for v in scores.values()),
        "burst_non_leads": sum(not v["is_burst_lead"] for v in scores.values()),
        "duplicates": sum(bool(v["duplicate_of"]) for v in scores.values()),
        "culled": sum(v["cull"] for v in scores.values()),
        "bursts": len({v["burst_group"] for v in scores.values() if v["burst_group"]}),
        "similarity_groups": len({v["similarity_group"] for v in scores.values() if v["similarity_group"]}),
        "scenes": len({v["scene_id"] for v in scores.values() if v["scene_id"] is not None}),
        "moments": dict(sorted(moments.items(), key=lambda kv: -kv[1])),
        "top": [{"asset_id": k, "filename": v["filename"], "aggregate": v["aggregate"]} for k, v in ranked[:10]],
        "bottom": [{"asset_id": k, "filename": v["filename"], "aggregate": v["aggregate"]} for k, v in ranked[-10:][::-1]],
    }


# ---------------------------------------------------------------- Immich + cache

def fetch_album_assets(album_id: str) -> list[dict]:
    """Sync Immich POST /search/metadata scoped to the album (paged)."""
    import httpx

    from memories.config import get_settings

    s = get_settings()
    out: list[dict] = []
    with httpx.Client(timeout=60, headers={"x-api-key": s.immich_api_key}, verify=s.immich_verify_tls) as c:
        for form in ("albumIds", "filter"):
            out, page = [], 1
            ok = True
            while page:
                body: dict[str, Any] = {"withExif": True, "size": 1000, "page": int(page)}
                if form == "albumIds":
                    body["albumIds"] = [album_id]
                else:
                    body["filter"] = {"albumIds": {"any": [album_id]}}
                r = c.post(s.immich_api + "/search/metadata", json=body)
                if r.status_code == 400:
                    ok = False
                    break
                r.raise_for_status()
                assets = r.json().get("assets", {})
                out.extend(assets.get("items", []))
                page = assets.get("nextPage")
            if ok:
                return out
    return out


def refresh_scores(album_id: str, raw_file: Path | None = None, assets: list[dict] | None = None) -> dict:
    """Rebuild the per-album cache from facet_raw.json + the Immich album. Returns the cache doc."""
    rp = raw_file or raw_path()
    raw = json.loads(Path(rp).read_text())
    if assets is None:
        assets = fetch_album_assets(album_id)
    scores = build_scores(raw, assets)
    doc = {
        "album_id": album_id,
        "built_at": time.time(),
        "facet_generated_at": raw.get("generated_at"),
        "facet_photos": len(raw.get("photos", {})),
        "album_images": sum(1 for a in assets if a.get("type", "IMAGE") == "IMAGE"),
        "album_videos": sum(1 for a in assets if a.get("type") == "VIDEO"),
        "summary": summarize(scores),
        "scores": scores,
    }
    tmp = cache_path(album_id).with_suffix(".tmp")
    tmp.write_text(json.dumps(doc))
    tmp.replace(cache_path(album_id))
    log.info("facet: album %s cached (%d scored / %d facet photos)", album_id, len(scores), doc["facet_photos"])
    return doc


_mem: dict[str, tuple[float, dict]] = {}


def load_doc(album_id: str, refresh: bool = False) -> dict | None:
    """Full cache document (summary + scores) or None when Facet has nothing for this album."""
    cp = cache_path(album_id)
    if refresh or (not cp.exists() and raw_path().exists()):
        try:
            refresh_scores(album_id)
        except Exception as e:  # noqa: BLE001 - signals are optional, never break the director
            log.warning("facet: refresh failed for %s: %s", album_id, e)
    if not cp.exists():
        return None
    mtime = cp.stat().st_mtime
    hit = _mem.get(album_id)
    if hit and hit[0] == mtime:
        return hit[1]
    doc = json.loads(cp.read_text())
    _mem[album_id] = (mtime, doc)
    return doc


def load_scores(album_id: str, refresh: bool = False) -> dict[str, dict]:
    """{asset_id: {aggregate, aesthetic, composition, face_quality, eye_sharpness, sharpness, exposure,
    color, dynamic_range, saliency, blink, burst_group, is_burst_lead, duplicate_of, similarity_group,
    scene_id, moment_labels, moment_confidence, subject_box, crop_9x16, cull, cull_reasons, ...}}.
    Scores are 0-10 (Facet scale). Empty dict when Facet has no data (never raises)."""
    doc = load_doc(album_id, refresh=refresh)
    return doc["scores"] if doc else {}


def shot_value(asset_id: str, semantic: float, scores: dict[str, dict], facet_weight: float = 0.4) -> float:
    """Blend: facet_weight * facet aggregate (0-10 -> 0-1) + (1-facet_weight) * semantic (0-1).
    Assets without a Facet score (videos) keep their semantic score unchanged."""
    s = scores.get(asset_id)
    if not s or s.get("aggregate") is None:
        return semantic
    return facet_weight * (s["aggregate"] / 10.0) + (1 - facet_weight) * semantic


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    args = sys.argv[1:]
    if not args:
        sys.exit("usage: python -m memories.facet_scores <album_id> [--raw PATH]")
    rf = Path(args[args.index("--raw") + 1]) if "--raw" in args else None
    d = refresh_scores(args[0], raw_file=rf)
    print(json.dumps({k: v for k, v in d.items() if k != "scores"}, indent=1))
