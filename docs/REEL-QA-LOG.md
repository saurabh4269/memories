# Reel QA log: Festive Hacks 2026 (album 47e3d2d0-21fa-4df7-8a2e-44f57597524b)

How each reel was scored: `uv run python server/scripts/eval_reel.py <cut.mp4> <reel.json> --cut N` runs the automatic checks (`memories/qa.py`) and writes a contact sheet with one frame per second and the safe box overlaid. I then looked at the sheet and scored the 10 criteria in docs/EDIT-RUBRIC.md from 0 to 10. All renders are 1080x1920 at 30 fps. Reel files are served at `https://memories-3870f5.centralindia.cloudapp.azure.com/director/files/reels/<id>/cut0_final.mp4`.

Score columns: Hook / Pacing / Variety / Framing / Captions / Story / People / Music / Ending / Technical / Total.

## Iteration 0: baseline (reel 9a152edb58a7, deployed code before this work)

| Cut | H | P | V | F | C | S | Pe | M | E | T | Total |
|---|---|---|---|---|---|---|---|---|---|---|---|
| cut0 "Hackathon ki Journey", wa_status, 29.7 s | 6 | 5 | 6 | 6 | 4 | 5 | 6 | 6 | 5 | 6 | **55** |
| cut1 "Team Moments Best Hits", 15.3 s | 6 | 4 | 4 | 6 | 3 | 4 | 4 | 6 | 3 | 6 | **46** |

The automatic checks flagged:
- cut0 runs 29.7 s, outside the 15-20 s WA status window.
- Video clips of 3.7, 4.6 and 4.2 s, plus one 5.6 s corridor walk in cut1.
- 4 low-value shots in cut0 (red-carpet walking, booths, an empty screen).
- 1-2 small captions per cut.
- The first cut lands at 2.3 s.
- cut1 ends on the robot, with no people.

The frame sheet shows two crossfades with ghosting. Cut1's "team" title is not true of its clips: organisers, booths and corridors.

## Iteration 1: grammar pass + team semantics (dev reels 7f682b03c0e7, 2536cf200473)

What changed:
- `grammar.py` enforces the edit grammar on every cut, from any director:
  - Shot value comes from people, group, mood and quality. Empty, corridor and walking shots are penalised.
  - Videos are trimmed to their best 1.5-3 s window, and each source is used at most once.
  - The hook is the best people shot (first cut at about 1.4 s). The ending is the best group shot, held 2.3-2.8 s.
  - Lengths per destination: wa_status 15-20, insta_reel 15-25, insta_story 10-15.
- Analysis v2 adds `activity`, `team_work`, `candid` and `main_subjects`, and the album was re-analysed.
- `team.py` derives the team from recurring Immich face clusters, the activity tags and 5 CLIP queries, and gives each asset a `team_score`.
- Intent parsing feeds a 70% team rule and a claim validator that checks titles and captions against the clips.
- Captions are at least 64 px (title 100), white with a stroke and shadow, inside x 60-950 / y 250-1540, and placed away from face boxes.
- Ken Burns goes from 1.00 to 1.08 toward the faces, alternating in and out.
- Photos come from the full-size source, and the crop falls back to blur-fill above 1.5x upscale.
- Music fades out over 1.2 s. WA status gets a 0.5 s fade to black at the end.
- The Flagsmith `render_profile` transition is now "cut".

| Reel | H | P | V | F | C | S | Pe | M | E | T | Total |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 7f682b03c0e7 cut0, team wa_status | 6 | 7 | 5 | 7 | 3 | 5 | 8 | 7 | 6 | 6 | 60 |
| 2536cf200473 cut0, team wa_status | 7 | 7 | 6 | 7 | 7 | 6 | 8 | 7 | 6 | 8 | **69** |

Problems found and fixed in this round:
- Devanagari mixed into a Latin title showed as tofu boxes. Mixed scripts are now cleaned.
- The prod flag was still xfade, which made the ghosting. It is now cut.
- Too few videos. Video share is now pushed toward 30%, team videos first.
- Swag and screen videos crept into the team cut. Only team or stage videos are allowed there now.
- Two shots of the same table appeared. Images with the same people and activity within 20 min now count as near-duplicates.

## Iteration 2: recap template + beat-correct music (39fe890f34d1, then prod d837ecf1ea9d)

What changed:
- New `recap` intent with a fixed slot order: team hook, 1 venue shot, sponsor, building, stage, robot, more building, team ending.
- Every cut is snapped to the beat of the track that actually plays. Before this, the beat came from one track while another was mixed in.
- Energetic and recap prompts use "Life of Riley". A track tagged `dev`/`hacker` will be preferred automatically once it lands.

| Reel | H | P | V | F | C | S | Pe | M | E | T | Total |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 39fe890f34d1 cut0, recap insta_reel, 23.2 s, with captions | 7 | 7 | 7 | 7 | 8 | 7 | 7 | 7 | 6 | 8 | **71** |

## Iteration 3: user feedback (prod, final)

What changed:
- Captions are off unless the prompt asks for them.
- A "building" request keeps only `team_working_at_laptops` and `coding_closeup` shots.
- Judges and organisers (stage, staff or mic shots, and the people who recur in them) never count as the team or the team ending.
- Stage-only prompts favour `stage_talk`.
- Truncated captions no longer end on a dangling stopword.

| Prompt (destination) | Reel id, cut0 | Length / shots | H | P | V | F | C* | S | Pe | M | E | T | Total |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| "hackathon ki yaadein, team ke saath, thoda emotional" (wa_status) | 40782ec6babd | 18.1 s / 9 | 7 | 7 | 6 | 7 | 8 | 6 | 8 | 7 | 7 | 8 | **71** |
| "energetic hackathon recap ... end on the team" (insta_reel) | d837ecf1ea9d | 23.2 s / 12 | 7 | 7 | 7 | 7 | 8 | 7 | 7 | 7 | 6 | 8 | **71** |
| "sirf stage aur talks" (insta_story) | beebf28676cb | 13.8 s / 6 | 7 | 7 | 6 | 7 | 8 | 6 | 6 | 7 | 6 | 7 | **67** |
| "team building intensely" (insta_reel) | d048101056da | 21.3 s / 11 | 6 | 7 | 6 | 7 | 8 | 6 | 8 | 7 | 7 | 8 | **70** |

\* Captions were turned off by the user's request, so this column scores only the absence of bad text. The automatic check's warning "0 captions (want 3-5)" is expected for these reels.

None of these reels has a hard fail: no black first frame, no adjacent duplicate, no clipping (peak -4.2 dB or lower), and every one is 9:16 with no letterbox bars.

Remaining weaknesses:
1. The album has no `team_group_pose` shot, so the ending is a laptop shot of the team rather than a posed photo.
2. Gemma found only 2 team videos, so team cuts run 12-15% video, below the 30% target. Faces are not clustered on videos either.
3. Stage-only cuts are mostly audience videos.
4. Landscape videos still get blur bands.
5. The second cut of each reel overlaps heavily with the first.
6. The agentic director's first round takes 9-15 s before it is forced to submit.
