#!/usr/bin/env bash
# Run a command on the Memories VM: ./vm.sh 'kubectl get pods -A'
# (multiplexed SSH, retries on connection failure)
# Host, user, and key: environment, else deploy/.vm.env, else the defaults below.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/.vm.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/.vm.env" || { set +a; exit 1; }
  set +a
fi
: "${MEMORIES_VM_HOST:?Set MEMORIES_VM_HOST in deploy/.vm.env (see deploy/.vm.env.example)}"
: "${MEMORIES_VM_USER:=azureuser}"
: "${MEMORIES_SSH_KEY:=$HOME/.ssh/id_ed25519}"
case "$MEMORIES_SSH_KEY" in
  '~/'*) MEMORIES_SSH_KEY="$HOME/${MEMORIES_SSH_KEY:2}" ;;
esac
mkdir -p ~/.ssh/cm
for i in 1 2 3 4 5 6; do
  ssh -i "$MEMORIES_SSH_KEY" -o ConnectTimeout=15 -o ServerAliveInterval=20 -o ControlMaster=auto \
      -o ControlPath=~/.ssh/cm/memories-%C -o ControlPersist=10m \
      "${MEMORIES_VM_USER}@${MEMORIES_VM_HOST}" "$@"; rc=$?
  [ $rc -ne 255 ] && exit $rc; sleep 5
done; exit 255
