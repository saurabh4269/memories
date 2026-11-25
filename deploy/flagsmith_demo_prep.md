# Flagsmith demo prep

Project 55989, Development environment 119871. Management API + Edge API only. No secrets in this log.

## 1. elder_mode speaker

Feature `elder_mode` 303493, segment override on `elders_hindi` 1203867 (priority 0, enabled).

Value (rest unchanged):

```json
{"large_text": true, "font_scale": 1.4, "voice_prompts": true, "ui_language": "hi-IN", "simple_home": true, "tts_speaker": "simran_hi_narration"}
```

Environment default is still the English elder_mode document, enabled.

Identity check:

- `nani-demo` — `elder_mode` enabled, value above, reason `TARGETING_MATCH; segment=elders_hindi`
- `chintu-demo` — `elder_mode` enabled with the default document (no `tts_speaker`), reason `DEFAULT`

## 2. Identities

Persisted via Edge `POST /api/v1/identities/`.

| identifier | traits | shot_coach |
|---|---|---|
| `nani-demo` | language=hi-IN, role=elder, name=Nani, cohort=beta | enabled, `TARGETING_MATCH; segment=beta_families` |
| `chintu-demo` | language=en-IN, role=kid | off, `DEFAULT` (outside the 25% bucket) |

## 3. shot_coach rollout

Feature `shot_coach` 303495. Environment default stays **off** (`{"max_cards":3}`).

| segment | id | rule | override |
|---|---|---|---|
| `beta_families` | 1203900 | trait `cohort` EQUAL `beta` | enabled, priority 0 |
| `shot_coach_rollout_25` | 1203901 | PERCENTAGE_SPLIT value `25`, property `$.identity.key` | enabled, priority 1 |

Property note: the condition was first created with property `id` (non-empty, as in the quickstart). On the current engine a named property is a trait lookup, and a missing trait matches nobody (0/16 persisted probes). Updated the same segment to `$.identity.key` so the split hashes the identity key. Transient probe after that: 9 of 40 identities got `TARGETING_MATCH; segment=shot_coach_rollout_25`. Probe identities were not persisted (`pct-probe-*` were created only to confirm the `id` property and then deleted).

`beta_families` has the lower priority number, so a beta identity is on even when they are also inside the 25%.

## 4. Experiment

`POST .../experiments/` while 459 was paused returned 409: "An active experiment already exists for this feature."

- Experiment **459** was **not deleted**. It was completed with `rollout_decision: control` so `director_strategy` keeps serving `single_shot` as the control. Status `completed`, `ended_at` 2026-11-25T09:54:17Z. Name still "Director strategy: agentic vs single-shot".
- Fresh experiment **460** "Agentic director vs single-shot (demo)". Hypothesis "The agentic director produces reels families share more". Feature `director_strategy` 303492. Metric `reel_shared` 424, expected direction increase. Rollout 100%, control value `single_shot`, variation `agentic` (option 36717) at 50%. Status **`created`**, `started_at` null. **Not started.**

Creating 460 installed its rollout override (system segment 1203903, variant 36717 weight 50) before start. Both demo identities currently evaluate `director_strategy` to `agentic` (`SPLIT; weight=50.0`). Environment default is still `single_shot`, enabled.

## 5. Off flags and health

- `ml_lite_mode` 303496 — environment default off. Identity reason `STATIC`.
- `peak_mode` 303498 — environment default off. Identity reason `STATIC`.
- `shot_coach` health — latest event 4215 at 2026-11-25T09:53:53Z, type `HEALTHY`, feature 303495, environment 119871, provider Webhook.
