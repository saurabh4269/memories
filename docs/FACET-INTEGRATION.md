# Facet integration: objective quality signals for shot selection

Facet ([ncoevoet/facet](https://github.com/ncoevoet/facet), MIT) runs on the VM next to Immich
(`/opt/facet`, container `facet`, `127.0.0.1:5005`, CPU `legacy` profile) and scores every
**photo** of the event. Videos are not scored: a missing asset id means "no signal", never "bad".

## Data flow

```
/opt/media/hackathon --(facet.py scan: scores, bursts, duplicates, moments, saliency)--> Facet SQLite
Facet SQLite --(scripts/facet_export.py inside the facet container)--> /srv/director/facet/facet_raw.json
facet_raw.json + Immich album --(memories.facet_scores.refresh_scores)--> /data/facet/<album_id>.json
```

Inside the director container `/data/facet` is `/srv/director/facet` on the host.

## Use it

```python
from memories.facet_scores import load_scores, shot_value

fs = load_scores(album_id)          # {asset_id: {...}}; {} if Facet has nothing; never raises
f = fs.get(asset_id)                # None for videos / unmatched assets
```

Every record holds these fields. Scores use Facet's 0-10 scale; `None` means not computed:

| field | meaning |
|---|---|
| `aggregate` | Facet's category-weighted overall score (0-10). **The one to rank on.** |
| `aesthetic`, `composition`, `face_quality`, `eye_sharpness`, `sharpness`, `color`, `exposure` | per-dimension 0-10 |
| `dynamic_range` (stops), `saliency` (subject area ratio 0-1), `face_count`, `category` | extra context |
| `blink` | bool: someone's eyes are closed |
| `burst_group` / `is_burst_lead` | `"b12"` or None / True for the best frame of the burst (and for every non-burst photo) |
| `duplicate_of` | asset id of the kept twin when this is a near-duplicate, else None |
| `similarity_group` | `"s3"`: visually similar set (CLIP cosine 0.85), wider than bursts |
| `scene_id` | int: chronological scene (capture-time gaps), Facet's story order |
| `moment_labels`, `moment_confidence` | zero-shot hackathon moment: `stage_presentation`, `audience`, `team_coding`, `group_photo`, `award_ceremony`, `networking`, `selfie_portrait`, `food_break`, `venue_signage`, `screen_demo`, `celebration` |
| `subject_box` | `[x0,y0,x1,y1]` normalised, saliency subject box (BiRefNet) |
| `crop_9x16` | `[x0,y0,x1,y1]` normalised 9:16 window centred on the subject, clamped to the frame |
| `cull`, `cull_reasons` | True plus the reasons: `blink`, `burst_non_lead`, `duplicate`, `junk:*` |

## Rules for the director

1. **Hard drops:** skip any photo with `f["cull"]`, meaning a blink, a non-lead burst frame or a
   duplicate. `director.usable()` already does this. Exception: when the requester names the
   person or moment and no other frame exists, let it through.
2. **Shot value** = `0.4 * aggregate/10 + 0.6 * semantic`, where semantic is your 0-1
   caption/team relevance. Use `shot_value(asset_id, semantic, fs)`; it returns `semantic`
   unchanged for videos so they are not penalised.
3. **One per similarity group:** when two picks share a `similarity_group`, keep the one with the
   higher `aggregate` unless the request needs both.
4. **9:16 crops:** prefer `crop_9x16` (or the centre of `subject_box`) over a face-less centre
   crop. When faces are known (`person_ids`), faces win and `subject_box` is the fallback.
   `pipeline.py` already sets `analysis.subject_center` from it.
5. **Story order:** sort by `scene_id`, then by time inside a scene. Within a reel aim for
   1-3 shots per scene rather than 8 shots from a single scene.
6. **Intent matching:** map request words to `moment_labels`. For example "stage", "pitch" or
   "demo" map to `stage_presentation`/`screen_demo`, "team" or "building" to
   `team_coding`/`group_photo`, and "winning" to `award_ceremony`. Add +0.1 semantic when the
   label matches. Use `moment_confidence` (0-1) to scale the bonus.
7. **Hook / opener:** the highest `aggregate` among `face_quality >= 6` and `eye_sharpness >= 6`
   photos makes a strong first frame. The closer should be a `group_photo`.
8. **Never** use Facet to drop videos, or to drop a photo only because `aggregate` is low when
   it is the only shot of a requested moment.

## Refresh

- After new photos: run the Facet scan and export on the VM, then rebuild the album cache:
  ```bash
  cd /opt/facet && docker exec facet python facet.py /data/photos/hackathon \
    && docker exec -i facet python - < export/facet_export.py > /srv/director/facet/facet_raw.json
  curl -X POST http://127.0.0.1:8010/v1/albums/<album_id>/facet/refresh
  ```
- HTTP: `GET /v1/albums/{id}/facet[?summary_only=true]` returns a summary (top/bottom 10,
  counts) and the per-asset scores. `POST /v1/albums/{id}/facet/refresh` rebuilds the cache.
- CLI: `python -m memories.facet_scores <album_id>`.
