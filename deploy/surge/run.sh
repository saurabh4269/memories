#!/usr/bin/env bash
# Mac-side entrypoint: copies the scripts to the VM and runs the surge loop there.
# Usage: deploy/surge/run.sh   (env knobs pass through: LIMIT N PAR CONC RESTART_AGENT AUTO_APPROVE RESTORE)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"
if [ -f "$DEPLOY_DIR/.vm.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$DEPLOY_DIR/.vm.env" || { set +a; exit 1; }
  set +a
fi
: "${MEMORIES_VM_HOST:?Set MEMORIES_VM_HOST in deploy/.vm.env (see deploy/.vm.env.example)}"
: "${MEMORIES_VM_USER:=azureuser}"
: "${MEMORIES_SSH_KEY:=$HOME/.ssh/id_ed25519}"
case "$MEMORIES_SSH_KEY" in
  '~/'*) MEMORIES_SSH_KEY="$HOME/${MEMORIES_SSH_KEY:2}" ;;
esac
scp -q -i "$MEMORIES_SSH_KEY" loop.sh burst.sh set_concurrency.sh watch_mem.sh fetch_photos.py \
  "${MEMORIES_VM_USER}@${MEMORIES_VM_HOST}:~/"
"$DEPLOY_DIR/vm.sh" "test -d ~/photos || python3 -I ~/fetch_photos.py ~/photos 40; LIMIT=${LIMIT:-700Mi} N=${N:-100} PAR=${PAR:-16} CONC=${CONC:-16} RESTART_AGENT=${RESTART_AGENT:-1} AUTO_APPROVE=${AUTO_APPROVE:-1} RESTORE=${RESTORE:-1} bash ~/loop.sh"
