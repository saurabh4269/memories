# Memories ops + sponsor-integration layer

## Architecture

```
 phones ──HTTPS──> Caddy ──> immich-server (docker compose, /opt/immich)  ── postgres, valkey
                                   │ IMMICH_MACHINE_LEARNING_URL=http://10.10.0.4:30003
                                   ▼
                    k3s (single node, same VM, traefik disabled)
                    ├─ ns immich: Deployment immich-machine-learning (v3.4.2, 2Gi limit, model cache hostPath /opt/immich-ml-cache, MODEL_TTL=300)
                    │             Service NodePort 30003 -> 3003
                    └─ ns nudgebee-agent: runner + forwarder (Helm chart nudgebee-agent, nodeAgent off) ──wss──> relay.nudgebee.com
 NudgeBee cloud: OOM event (HIGH) -> AI investigation -> workflow memories-ml-surge -> in-app approval
              -> HTTP PATCH Flagsmith __future__ (ml_lite_mode ON) -> HTTP POST Flagsmith Feature Health (shot_coach UNHEALTHY)
 Memories backend/app read flags from Flagsmith Edge API (ml_lite_mode, peak_mode, render_profile, shot_coach, ...)
```

Why ML is in Kubernetes: it is the part that struggles under a Diwali-night upload burst (face detection + CLIP run per photo), so it is the part NudgeBee watches.

VM (`MEMORIES_VM_NAME` in `.vm.env`): Azure centralindia, Ubuntu 24.04, Standard_D16as_v5 (16 vCPU / 64 GB), private IP 10.10.0.4. The surge calibration and benchmarks were measured when it was a D8as_v5 (8 vCPU / 32 GB). Only this VM was touched; NSG unchanged (6443 not exposed).

## Files
| Path | What |
|---|---|
| `.vm.env.example` | copy to `.vm.env` (gitignored) for host, SSH user, key, kube context, and env-file paths |
| `env.sh` | `source` it: loads `MEMORIES_ENV_FILE` and, when the file exists, `MEMORIES_IMMICH_ENV` (no values in this repo) |
| `vm.sh`, `tunnel.sh` | SSH to `$MEMORIES_VM_USER@$MEMORIES_VM_HOST` (multiplexed, retries); tunnel 6443 for local kubectl |
| `k8s/immich-ml.yaml`, `k8s/apply-ml.sh` | ML Namespace/Deployment/Service; `apply-ml.sh` fills the version from `/opt/immich/.env` |
| `flagsmith_features.json` | Flagsmith org/project/env ids and feature ids |
| `nudgebee/memories-ml-surge.workflow.yaml` | the workflow (`__FLAGSMITH_ENV_KEY__` placeholder, substituted at apply time) |
| `surge/` | burst + OOM scenario, calibration numbers and timings (`surge/README.md`) |

## Connection settings

`vm.sh`, `tunnel.sh`, `surge/run.sh`, and `env.sh` take connection settings from the environment. When `deploy/.vm.env` exists they source it first. Each assignment in that file keeps a variable you already exported, and otherwise uses the value after `:-`. Script defaults apply only for variables that are still unset. Copy `deploy/.vm.env.example` to `deploy/.vm.env` for this machine. Paths inside the scripts are relative to the script directory (`"$(cd "$(dirname "$0")" && pwd)"`).

| Variable | Used for | If still unset |
|---|---|---|
| `MEMORIES_VM_HOST` | SSH and scp host (`vm.sh`, `tunnel.sh`, `surge/run.sh`) | required; the script exits |
| `MEMORIES_VM_USER` | SSH user | `azureuser` |
| `MEMORIES_SSH_KEY` | private key for `ssh` and `scp` | `$HOME/.ssh/id_ed25519` |
| `MEMORIES_VM_NAME` | this VM's name (this README) | unset; not read by the scripts |
| `MEMORIES_KUBE_CONTEXT` | `kubectl --context` after the tunnel is up | unset; not passed to `ssh` |
| `MEMORIES_KUBECONFIG` | kubeconfig for that local client | unset here; example uses `$HOME/.kube/config` |
| `MEMORIES_ENV_FILE` | keys sourced by `env.sh` | `knowledge-dump/festive-hacks-context/.env` under the repo root |
| `MEMORIES_IMMICH_ENV` | optional Immich keys sourced by `env.sh` | `knowledge-dump/azure/immich.env` under the repo root |

## Commands
```bash
cd deploy
./vm.sh 'kubectl get pods -A'                       # reads deploy/.vm.env
# local kubectl through the tunnel (values from .vm.env):
#   set -a; . ./.vm.env; set +a; ./tunnel.sh &
#   export KUBECONFIG="$MEMORIES_KUBECONFIG"
#   kubectl --context "$MEMORIES_KUBE_CONTEXT" get pods -A
k8s/apply-ml.sh                                     # (re)deploy Immich ML
# On the VM, compose changes made for this:
#   /opt/immich/.env: IMMICH_MACHINE_LEARNING_URL=http://10.10.0.4:30003
#   /opt/immich/docker-compose.override.yml: immich-machine-learning moved to profile "compose-ml" (not started)
#   rollback: rm the override, remove the env line, docker compose up -d

# NudgeBee (env-only auth)
source env.sh; nbctl workflow list                  # nbctl v0.0.5 in ~/.local/bin (also ~/nbctl on the VM)
R=$(mktemp); sed "s/__FLAGSMITH_ENV_KEY__/$FLAGSMITH_ENV_KEY/" nudgebee/memories-ml-surge.workflow.yaml > $R
nbctl workflow validate $R && nbctl workflow apply $R   # apply = create/update by name; new workflows start PAUSED
nbctl workflow resume 62fc4634-bdcb-45bf-a2ee-7b312c9e13d7

# Demo loop
surge/run.sh                                        # burst -> OOM -> event -> investigation -> approval -> flag -> restore
AUTO_APPROVE=0 RESTORE=0 surge/run.sh               # live demo: approve in the NudgeBee UI yourself
```

Approval by API (nbctl approve is broken, needs account_id): RPC `workflow_complete_approval` with `task_id: approve_lite_mode` (see `surge/loop.sh`).

## IDs (no secrets)
- NudgeBee account `festive-kind` (id in `.env` NUDGEBEE_ACCOUNT_ID). The k3s agent connected with the existing agent key; events from k3s show `cluster=festive-kind`. No conflict seen (the old kind cluster is gone).
- Workflow `memories-ml-surge`: `62fc4634-bdcb-45bf-a2ee-7b312c9e13d7` (ACTIVE). Old `festive-event-approve-flagsmith-toggle` (`9cdd8353-…`) is PAUSED (it fired on any HIGH event).
- NudgeBee secrets: `flagsmith_api_key` (Flagsmith org key, pre-existing), `flagsmith_health_webhook` (Feature Health webhook URL with token).
- Flagsmith project 55989, env Development 119871: `shot_coach` 303495, `ml_lite_mode` 303496, `render_profile` 303497, `peak_mode` 303498 (pre-existing, untouched: `director_strategy` 303492, `elder_mode` 303493, `festive_livetest` 303221).

## Calibration and timings (live)
See `surge/README.md`. Summary: working set under a 100-photo burst is ~0.9 GiB anon (2Gi limit: no OOM). With the limit at 700Mi and concurrency 16/16 the container is OOMKilled ~10 s into the burst. Take 1: OOM -> NudgeBee event ~2 s; event -> investigation.completed / execution ~3 min 46 s; approval -> Flagsmith edge `ml_lite_mode=true` 6 s.

## Honesty notes
- The OOM is staged: 700Mi is deliberately below the measured ~0.9 GiB working set, and Immich job concurrency is raised to 16 to make the burst bite in seconds. Production values: 2Gi limit, concurrency 2.
- "Sped-up investigation" in a demo cut: the real event -> investigation.completed delay was ~3.8 min; any shortened video should say so.
- The approval in the scripted loop is done via RPC (same effect as the in-app button, which is not exercised by the script).
- NudgeBee's eBPF node agent is off (reliability first); events come from the Kubernetes API watcher.
- The k3s cluster reports under the account name `festive-kind`, which was created for an earlier kind cluster.
- Photos are CC0/public-domain Wikimedia Commons images (attribution in `~/photos/ATTRIBUTION.tsv` on the VM); copies get random trailing bytes to defeat dedupe.
