# Submission checklist (Festive Hacks, §8)

Deadline: submit on the Festive Hacks page (https://www.wemakedevs.org/hackathons/festivehacks) **before 5:00 PM IST, 25 Nov 2026**.

| # | Requirement | Where it is satisfied | Status |
|---|---|---|---|
| 1 | Submitted through the Festive Hacks page | Festive Hacks site form (repo URL + video URL) | pending |
| 2 | Public repository | `github.com/saurabh4269/memories` (commands below) | pending: repo not created yet |
| 3 | README with setup instructions others can follow | [`README.md`](../README.md) "Setup" sections 1-8; [`server/README.md`](../server/README.md), [`deploy/README.md`](../deploy/README.md), root [`Makefile`](../Makefile) | mostly done; section 8 (Flutter app build) still has a TODO |
| 4 | Demo video of the working project | README "Demo video" section; script in [`docs/DEMO-SCRIPT.md`](DEMO-SCRIPT.md) | pending: URL is `TODO` in README |
| 5 | Uses Flagsmith + NudgeBee + Sarvam AI | README "How each sponsor tool does real work"; code: `server/src/memories/sarvam.py`, `analysis.py`, `voiceover.py`, `dictate.py` (Sarvam); `server/src/memories/flags.py`, `deploy/flagsmith_features.json` (Flagsmith); `deploy/nudgebee/memories-ml-surge.workflow.yaml`, `deploy/surge/` (NudgeBee) | done |
| 6 | Disclose AI coding assistant use (Rule 7) | README "AI assistance disclosure" | done |
| 7 | Main coding/design work began after the hackathon started (Rule 4) | First commit `e97f36a` at 2026-11-25 12:19 IST (hacking started 11:30 AM IST); Immich fork taken from upstream `eb97880`, our changes listed in [`app/NOTICE.md`](../app/NOTICE.md) | done (NOTICE change list still TODO) |
| 8 | Team ownership agreed (Rule 10) | README "Team" section | done (single member: Saurabh Gupta); confirm |
| 9 | *(judging)* Main flow works end to end live | README "Demo video", `docs/DEMO-SCRIPT.md` | pending: verify before recording |
| 10 | *(judging)* Each sponsor tool does real work and is visible in the demo | README sponsor tables + video | pending (video) |
| 11 | *(NudgeBee blog)* Human approval before any mutating action | NudgeBee workflow approval step (`deploy/nudgebee/…workflow.yaml`), `AUTO_APPROVE=0 deploy/surge/run.sh` | done |

Licensing: root [`LICENSE`](../LICENSE) is AGPL-3.0 (we ship a fork of Immich); [`app/LICENSE`](../app/LICENSE) + [`app/NOTICE.md`](../app/NOTICE.md) for the fork; music is CC BY 4.0 (Kevin MacLeod) with attribution in [`server/assets/music/CREDITS.md`](../server/assets/music/CREDITS.md) and `tracks.json`; Noto fonts are OFL 1.1 ([`server/assets/fonts/OFL.txt`](../server/assets/fonts/OFL.txt)).

## Before pushing

1. Refresh the app copy: `scripts/sync_app.sh` (then fill the TODO list in `app/NOTICE.md`).
2. Fill README TODOs (demo video URL, Flutter build steps, licence TODO can be removed now that `LICENSE` exists).
3. Re-run the secret scan on exactly what will be committed:

```bash
cd /Users/saurabh/.t3/projects/memories
git add -A --dry-run | sed -E "s/^add '(.*)'$/\1/" > /tmp/files.txt
rm -rf /tmp/stage && mkdir /tmp/stage && rsync -a --files-from=/tmp/files.txt . /tmp/stage/
gitleaks dir /tmp/stage --redact --no-banner
git add -A --dry-run | grep -E 'knowledge-dump|\.env$|\.sqlite|kubeconfig|\.pem|data/' || echo "clean"
```

4. Decide whether the VM public IP / SSH user hard-coded in `deploy/vm.sh`, `deploy/tunnel.sh`, `deploy/surge/run.sh` and `deploy/README.md` may be public (they are not credentials; the SSH key itself is not in the repo). Decide whether `PLAN.md` should be public.

## Create and push the public repo (run after review)

```bash
cd /Users/saurabh/.t3/projects/memories
git checkout -b submission 2>/dev/null || true   # optional; or stay on main
git add -A
git status --short | head -50                    # eyeball: no knowledge-dump/, .env, data/
git commit -m "Memories: Festive Hacks submission"
git branch -M main                               # if you used a branch, merge it first
gh repo create saurabh4269/memories --public --source . --remote origin --push \
  --description "Memories: AI director that turns festive family photos into reels (Sarvam AI + Flagsmith + NudgeBee, on Immich)"
gh repo view saurabh4269/memories --web
```

If the repo already exists: `git remote add origin git@github.com:saurabh4269/memories.git && git push -u origin main`.
