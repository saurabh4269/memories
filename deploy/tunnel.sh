#!/usr/bin/env bash
# Local kubectl via SSH tunnel. In another shell, after `set -a; . ./.vm.env; set +a`:
#   ./tunnel.sh &
#   export KUBECONFIG="$MEMORIES_KUBECONFIG"
#   kubectl --context "$MEMORIES_KUBE_CONTEXT" get pods
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
exec ssh -i "$MEMORIES_SSH_KEY" -N -o ExitOnForwardFailure=yes -L 6443:127.0.0.1:6443 \
  "${MEMORIES_VM_USER}@${MEMORIES_VM_HOST}"
