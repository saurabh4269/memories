#!/usr/bin/env bash
# Runs ON THE VM (copied by run.sh). Full demo loop:
#   low ML limit -> Diwali burst upload -> OOMKilled -> NudgeBee HIGH event -> investigation.completed
#   -> workflow memories-ml-surge waiting approval -> approve (RPC) -> Flagsmith ml_lite_mode ON (Edge API) -> restore.
# Env (from ~/.memories.env): NUDGEBEE_*, FLAGSMITH_ORG_API_KEY, FLAGSMITH_ENV_KEY, IMMICH_API_KEY
# Knobs: LIMIT (700Mi) N (100) PAR (16) CONC (16) RESTART_AGENT (1) AUTO_APPROVE (1) RESTORE (1)
set -uo pipefail
source ~/.memories.env
LIMIT=${LIMIT:-700Mi}; N=${N:-100}; PAR=${PAR:-16}; CONC=${CONC:-16}
RESTART_AGENT=${RESTART_AGENT:-1}; AUTO_APPROVE=${AUTO_APPROVE:-1}; RESTORE=${RESTORE:-1}
WF=${WF:-62fc4634-bdcb-45bf-a2ee-7b312c9e13d7}; FEAT=303496; FS=https://api.flagsmith.com
NB=~/nbctl; NS=immich; DEP=immich-machine-learning
ts(){ date +%s; }; log(){ echo "[$(date +%T)] $*"; }
fs_patch(){ curl -s -o /dev/null -w '%{http_code}' -X PATCH "$FS/api/__future__/environments/$FLAGSMITH_ENV_KEY/features/$FEAT/" \
  -H "Authorization: Api-Key $FLAGSMITH_ORG_API_KEY" -H 'Content-Type: application/json' -d "{\"environment_default\":{\"enabled\":$1}}"; }
edge_flag(){ curl -s https://edge.api.flagsmith.com/api/v1/flags/ -H "X-Environment-Key: $FLAGSMITH_ENV_KEY" | jq -r '.[]|select(.feature.name=="ml_lite_mode")|.enabled'; }
rpc(){ curl -s https://app.nudgebee.com/api/rpc -H 'content-type: application/json' -H "Authorization: Bearer $NUDGEBEE_API_KEY" -d "$1"; }

log "pre: ml_lite_mode edge=$(edge_flag); forcing off -> HTTP $(fs_patch false)"
if [ "$RESTART_AGENT" = 1 ]; then
  log "restarting NudgeBee runner (clears 1h per-workload alert suppression)"
  kubectl -n nudgebee-agent rollout restart deploy/nudgebee-agent-runner >/dev/null
  kubectl -n nudgebee-agent rollout status deploy/nudgebee-agent-runner --timeout=120s >/dev/null
  for i in $(seq 1 30); do kubectl -n nudgebee-agent logs deploy/nudgebee-agent-runner --tail=200 2>/dev/null | grep -q 'relay connected' && break; sleep 2; done
  log "runner: $(kubectl -n nudgebee-agent logs deploy/nudgebee-agent-runner --tail=200 | grep -c 'relay connected') relay-connected line(s)"
fi
log "setting $DEP memory limit to $LIMIT (deliberately low) and Immich concurrency faceDetection/smartSearch=$CONC"
kubectl -n $NS set resources deploy/$DEP -c machine-learning --limits=memory=$LIMIT --requests=memory=512Mi >/dev/null
kubectl -n $NS rollout status deploy/$DEP --timeout=180s >/dev/null
bash ~/set_concurrency.sh "$CONC" "$CONC" >/dev/null
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
( bash ~/watch_mem.sh 240 > ~/mem_take.log & )
log "burst: uploading $N photos, $PAR parallel"
bash ~/burst.sh ~/photos "$N" "$PAR"
T_OOM=""
for i in $(seq 1 120); do
  r=$(kubectl -n $NS get pod -l app=$DEP -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}')
  [ "$r" = OOMKilled ] && { T_OOM=$(ts); break; }; sleep 2
done
[ -z "$T_OOM" ] && { log "no OOMKill within 4 min; lower LIMIT or raise N/CONC"; exit 1; }
log "OOMKilled: $(kubectl -n $NS get pod -l app=$DEP -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.finishedAt}') (peak anon: $(sort -t= -k2 -n ~/mem_take.log | tail -1))"
T_EV=""
for i in $(seq 1 60); do
  ev=$($NB events list --limit 10 --start-time "$T0" --format json 2>/dev/null | jq -r 'if type=="array" then . else [] end | .[] | select(.subject_namespace=="immich" and .aggregation_key=="pod_oom_killer_enricher") | "\(.id) \(.priority) \(.title)"' | head -1)
  [ -n "$ev" ] && { T_EV=$(ts); break; }; sleep 5
done
log "NudgeBee event: ${ev:-none}  (OOM->event $(( ${T_EV:-$(ts)} - T_OOM ))s)"
EX=""; T_EX=""
for i in $(seq 1 120); do
  EX=$($NB workflow list-executions $WF --limit 5 --format json 2>/dev/null | jq -r --arg t "$T0" '.executions[]? | select(.start_time > $t and .status=="RUNNING") | .id' | tail -1)
  [ -n "$EX" ] && { T_EX=$(ts); break; }; sleep 5
done
[ -z "$EX" ] && { log "no workflow execution within 10 min"; exit 1; }
log "workflow execution $EX RUNNING (approval waiting). event->investigation.completed/execution $(( T_EX - ${T_EV:-T_OOM} ))s"
if [ "$AUTO_APPROVE" = 1 ]; then
  sleep 5
  T_AP=$(ts)
  rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"workflow_complete_approval\",\"params\":{\"request\":{\"account_id\":\"$NUDGEBEE_ACCOUNT_ID\",\"workflow_id\":\"$WF\",\"execution_id\":\"$EX\",\"task_id\":\"approve_lite_mode\",\"status\":\"approve\",\"comments\":\"Diwali surge: switch to lite ML\"}}}" | jq -c '.result // .error'
  for i in $(seq 1 60); do [ "$(edge_flag)" = true ] && break; sleep 1; done
  log "Edge API ml_lite_mode=$(edge_flag)  (approval->flag visible on edge $(( $(ts) - T_AP ))s)"
  sleep 5; $NB workflow get-execution $WF $EX --format json 2>/dev/null | jq -c '{status, tasks: [ (.tasks // .task_executions // [])[]? | {id:(.task_id // .id), status, code:(.output.status_code // null)} ]}' 2>/dev/null
else
  log "approve it in the NudgeBee UI (Automations -> Executions), then watch the flag"; exit 0
fi
if [ "$RESTORE" = 1 ]; then
  log "restore: ml_lite_mode off -> HTTP $(fs_patch false); ML limit 2Gi; concurrency 2/2"
  kubectl -n $NS set resources deploy/$DEP -c machine-learning --limits=memory=2Gi --requests=memory=1Gi >/dev/null
  bash ~/set_concurrency.sh 2 2 >/dev/null
  WH=$(curl -s $FS/api/v1/projects/55989/feature-health/providers/ -H "Authorization: Api-Key $FLAGSMITH_ORG_API_KEY" | jq -r '.[0].webhook_url')
  log "shot_coach feature health -> healthy: HTTP $(curl -s -o /dev/null -w '%{http_code}' -X POST "$WH" -H 'Content-Type: application/json' -d '{"feature":"shot_coach","environment":"Development","status":"healthy","reason":{"text_blocks":[{"title":"NudgeBee","text":"surge over; ML limit restored"}],"url_blocks":[]}}')"
  log "note: one OOM also yields a CrashLoopBackOff event; the workflow filter only matches pod_oom_killer_enricher"
fi
