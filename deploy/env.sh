# source this: loads keys without echoing them.
# Optional deploy/.vm.env sets MEMORIES_ENV_FILE and MEMORIES_IMMICH_ENV.
# Directory is this file's directory (bash or zsh). Fall back to $0, then the working directory.
_src="${BASH_SOURCE[0]:-$0}"
_here="$(cd "$(dirname "$_src")" && pwd)"
if [ -f "$_here/.vm.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$_here/.vm.env" || { set +a; return 1; }
  set +a
fi
_root="$(cd "$_here/.." && pwd)"
: "${MEMORIES_ENV_FILE:=$_root/knowledge-dump/festive-hacks-context/.env}"
: "${MEMORIES_IMMICH_ENV:=$_root/knowledge-dump/azure/immich.env}"
set -a; source "$MEMORIES_ENV_FILE"; set +a
export NUDGEBEE_ENDPOINT=https://app.nudgebee.com
[ -f "$MEMORIES_IMMICH_ENV" ] && { set -a; source "$MEMORIES_IMMICH_ENV"; set +a; }
export FS=https://api.flagsmith.com
