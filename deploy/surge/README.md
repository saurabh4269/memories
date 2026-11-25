# Diwali-night surge scenario (Immich ML OOM)

`run.sh` (Mac) copies the scripts to the VM and runs `loop.sh` there (the VM's network to NudgeBee/Flagsmith is steadier than venue wifi).

```bash
deploy/surge/run.sh                      # full loop, auto-approve, restore afterwards
RESTART_AGENT=0 deploy/surge/run.sh      # first take after a fresh agent install (no suppression yet)
AUTO_APPROVE=0 RESTORE=0 deploy/surge/run.sh   # stop at the approval; approve live in the NudgeBee UI
```
Knobs: `LIMIT` (700Mi) `N` photos (100) `PAR` parallel uploads (16) `CONC` Immich faceDetection/smartSearch concurrency (16).

Files: `burst.sh` (parallel `POST /api/assets`; 64 random bytes appended per copy so checksum dedupe never skips), `fetch_photos.py` (40 CC0/public-domain group photos from Wikimedia Commons, `~/photos/ATTRIBUTION.tsv` on the VM), `set_concurrency.sh` (`PUT /api/system-config`), `watch_mem.sh` (cgroup v2 `memory.stat anon`, `memory.current`, `oom_kill`, restarts every 2 s).

## Calibration (measured live 2026-11-25, VM 8 vCPU / 32 GB, Immich v3.4.2, CPU ONNX)

`memory.current` includes ~1 GB of page cache (model files), which the kernel reclaims instead of OOM-killing; at 2Gi `memory.current` sat at the limit (`memory.events max` 925) with **no** OOM. Calibrate on `anon` instead.

| ML limit | Concurrency face/smart | Burst | Peak anon | Result |
|---|---|---|---|---|
| 2Gi | 2/2 (default) | 8 photos | idle with CLIP + buffalo_l loaded: ~480-750 MiB total | OK; 212 faces, smart search 9 hits |
| 2Gi | 8/8 | 100 photos | 894 MiB (total 1.97 GiB incl. cache) | OK, no OOM |
| 2Gi | 8/8 | 100 photos (repeat) | ~890 MiB | OK, no OOM |
| **700Mi** | **16/16** | **100 photos** | 672 MiB at 7 s, then killed | **OOMKilled ~10 s after the burst started**, then CrashLoopBackOff |

So the real working set under a 100-photo burst is ~0.9 GiB anon; 700Mi is deliberately below it. Production setting: 2Gi limit / 1Gi request, concurrency 2/2.

## Full loop, take 1 (live, 2026-11-25 IST)

| Step | Time (UTC) | Delta |
|---|---|---|
| burst start (100 photos, all HTTP 201 in 2 s) | 09:11:05 | |
| container OOMKilled | 09:11:15 | burst -> OOM 10 s |
| NudgeBee HIGH event `Pod immich/immich-machine-learning-… was OOMKilled` (`pod_oom_killer_enricher`) | 09:11:17 | OOM -> event ~2 s |
| `investigation.completed` -> execution started (approval waiting) | 09:15:03 | event -> execution ~3 min 46 s |
| approval via RPC `workflow_complete_approval` | ~09:15:12 | |
| Flagsmith PATCH 200, feature-health UNHEALTHY on `shot_coach` (09:15:14), Edge API `ml_lite_mode=true` | 09:15:18 | approval -> edge flag 6 s |
| restore: flag off (200), limit 2Gi, concurrency 2/2, shot_coach healthy | 09:15:25 | |

Only one execution: the filter requires `event_type == "pod_oom_killer_enricher"`, so the CrashLoopBackOff event that follows every OOM does not start a second run. Full log: `take1.log`.

## Rerun notes
- NudgeBee suppresses repeat alerts for the same workload for 1 hour; `loop.sh` restarts `deploy/nudgebee-agent-runner` first (default `RESTART_AGENT=1`).
- Each take adds 100 photos to the Immich library (admin user). Delete them in the UI if the album gets noisy.
- If no OOM: lower `LIMIT` (600Mi) or raise `N`/`CONC`.
