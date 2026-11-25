"""Export Facet scores to a flat JSON for the Memories director.

Runs INSIDE the Facet container (it imports Facet's own api/ package so scenes and
similarity groups use Facet's algorithms, not a re-implementation):

    docker exec -i facet python - < facet_export.py > /srv/director/facet/facet_raw.json

Output: {"generated_at", "profile", "photos": {path: {...per-photo columns...,
"scene_id", "similarity_group"}}}. The director's memories.facet_scores maps these
paths onto Immich asset ids (filename + capture time).
"""
import json
import sqlite3
import sys
import time

sys.path.insert(0, "/app")

COLS = [
    "path", "filename", "date_taken", "image_width", "image_height", "aggregate", "aesthetic",
    "comp_score", "composition_pattern", "face_count", "face_ratio", "face_quality",
    "eye_sharpness", "tech_sharpness", "color_score", "exposure_score", "dynamic_range_stops",
    "isolation_bonus", "is_blink", "burst_group_id", "is_burst_lead", "duplicate_group_id",
    "is_duplicate_lead", "category", "tags", "narrative_moment", "narrative_moment_confidence",
    "subject_bbox", "subject_sharpness", "subject_prominence", "subject_placement", "junk_kind",
    "aesthetic_iaa", "face_quality_iqa", "liqe_score", "top_picks_score",
]


def export(db: str) -> dict:
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    have = {r[1] for r in conn.execute("PRAGMA table_info(photos)")}
    cols = [c for c in COLS if c in have]
    photos = {r["path"]: dict(r) for r in conn.execute(f"SELECT {', '.join(cols)} FROM photos")}

    # Facet's own groupings (computed on the fly in its API; cache-free here).
    try:
        from api.similarity_groups import compute_similarity_groups

        for gi, g in enumerate(compute_similarity_groups(conn, use_cache=False), 1):
            for p in g.get("paths", []):
                if p in photos:
                    photos[p]["similarity_group"] = gi
                    photos[p]["is_similarity_best"] = int(p == g.get("best_path"))
    except Exception as e:  # noqa: BLE001
        print(f"similarity groups failed: {e}", file=sys.stderr)
    try:
        from api.routers.scenes import compute_scenes

        for s in compute_scenes(conn, use_cache=False) if "use_cache" in compute_scenes.__code__.co_varnames else compute_scenes(conn):
            for ph in s.get("photos", []):
                p = ph.get("path") if isinstance(ph, dict) else ph
                if p in photos:
                    photos[p]["scene_id"] = s.get("scene_id")
    except Exception as e:  # noqa: BLE001
        print(f"scenes failed: {e}", file=sys.stderr)
    # burst members inherit their lead's scene (scenes are built over burst leads)
    lead_scene = {v["burst_group_id"]: v.get("scene_id") for v in photos.values()
                  if v.get("burst_group_id") is not None and v.get("is_burst_lead")}
    for v in photos.values():
        if v.get("scene_id") is None and v.get("burst_group_id") in lead_scene:
            v["scene_id"] = lead_scene[v["burst_group_id"]]
    return {"generated_at": time.time(), "source": "facet", "photos": photos}


def main() -> None:
    import os

    doc = export(os.environ.get("DB_PATH", "/app/data/photo_scores_pro.db"))
    json.dump(doc, sys.stdout, default=str)


if __name__ == "__main__":
    main()
