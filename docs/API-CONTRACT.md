# Memories director API contract (shared by all agents)

Base URL (public): `https://memories-3870f5.centralindia.cloudapp.azure.com/director`
All responses JSON unless noted. All media URLs returned are absolute https. CORS open. No auth for the hackathon (member identity passed as `member`).
Real album: "Festive Hacks 2026" id `47e3d2d0-21fa-4df7-8a2e-44f57597524b`.

## Existing (live)
| Method | Path | Notes |
|---|---|---|
| GET | /v1/albums | list albums |
| POST | /v1/albums/{id}/analyse | (re)analyse |
| GET | /v1/albums/{id}/coach?member=&lang= | up to 3 missing-shot cards `{cards:[{title, tip, lang}], disabled?}` (gated by Flagsmith `shot_coach` for the member identity) |
| POST | /v1/reels | `{album_id, prompt, destination: wa_status|insta_reel|insta_story, member_name, language}` -> `{reel_id, cuts:[{title, why, preview_url, cover_url, final_url, final_status, clips, music}], timings, trace, mode}` |
| GET | /v1/reels/{id} | status incl. final render |
| POST | /v1/reels/{id}/final/{cut} | returns final mp4 url (ready or renders) |
| POST | /v1/reels/{id}/shared | `{cut, target}` -> Flagsmith track_event reel_shared |
| GET | /v1/members/flags?member=&language=&role= | `{elder_mode:{enabled,value}, shot_coach:{...}, director_strategy, ml_lite_mode, peak_mode}` |
| POST | /v1/extras/voice-prompt | multipart `audio` (+ `names`, `language`) -> `{intent:{transcript, request, people[], include[], exclude[], mood, music, destination}, engine_used}` |
| POST | /v1/extras/invite | multipart `image` (+ `album_id`) -> `{invite, shot_list}` |
| POST | /v1/extras/voiceover | `{text, language, speaker?}` -> `{audio_url, duration_s}` |
| POST | /v1/extras/confirmation | `{language, name?}` -> spoken "reel ready" audio |
| GET | /studio | fallback web UI |

## New (being built now; build against these shapes)
| Method | Path | Owner | Shape |
|---|---|---|---|
| GET | /v1/reels/{id}/cuts/{cut}/edl | editor agent | `{cut, title, duration_s, music:{url, bpm, start_s}, clips:[{asset_id, type: photo|video, media_url, poster_url, in_s, out_s, hold_s, start_s, duration_s, caption, kenburns:{from,to,focus:[x,y]}}], captions:[...], transitions}` used by the app's live preview player |
| GET | /v1/assets/{asset_id}/image?size=preview|thumbnail | editor agent | proxied JPEG from Immich |
| GET | /v1/assets/{asset_id}/video | editor agent | proxied mp4 (HTTP Range supported) from Immich playback |
| POST | /v1/reels/{id}/edit | editor agent | `{cut, clips:[{asset_id, in_s?, out_s?, hold_s?, caption?}], music_mood?, title?}` -> new cut `{cut, preview_url, final_url, final_status}` (re-render using segment cache) |
| GET | /v1/reels/{id}/cuts/{cut}/alternatives?slot= | editor agent | `{alternatives:[{asset_id, poster_url, why}]}` for swapping a clip |
| GET | /v1/reels/{id}/cuts/{cut}/otio | editor agent | downloads `.otio` (OpenTimelineIO JSON) referencing original media URLs |
| POST | /v1/join/{album_id}/invite | join agent | `{created_by?}` -> `{code, join_url: "memories://join?code=...&server=...", web_url, qr_png_url, expires_at}` |
| POST | /v1/join/redeem | join agent | `{code, name, language, role}` -> `{server_url, email, password, album_id, member_id}` (creates an Immich user, adds as album editor) |
| GET | /v1/post/channels | postiz agent | `{channels:[{id, provider, name, avatar}]}` |
| POST | /v1/reels/{id}/post | postiz agent | `{cut, channel_ids:[...], caption}` -> `{posts:[{channel, status, url?}]}` (uploads final mp4 to Postiz, posts now) |

Server code: `/Users/saurabh/.t3/projects/memories/server/src/memories/`. New features go in NEW router modules (`editor_api.py`, `join_api.py`, `postiz_api.py`) exposing `router = APIRouter()`; `api.py` auto-includes `memories.editor_api`, `memories.join_api`, `memories.postiz_api` when importable.

Flutter fork: `/Users/saurabh/.t3/projects/memories/knowledge-dump/repos/immich-mobile-try/mobile`. New Memories features live in `lib/memories/<feature>/` as self-contained widgets/services; the integration agent wires routes, navigation and `pubspec.yaml`.
