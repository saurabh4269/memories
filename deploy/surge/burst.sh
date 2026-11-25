#!/usr/bin/env bash
# Runs ON THE VM. Uploads N unique photos to Immich in parallel (a "Diwali-night burst").
# Usage: IMMICH_API_KEY=... burst.sh <photo_dir> <count> [parallel] [immich_url]
# Each upload gets random trailing bytes so Immich's checksum dedupe never skips it.
set -euo pipefail
DIR=$1; N=${2:-100}; P=${3:-12}; URL=${4:-http://127.0.0.1:2283}
: "${IMMICH_API_KEY:?set IMMICH_API_KEY}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mapfile -t SRC < <(ls "$DIR"/*.jpg)
TAG=$(date +%s)
for i in $(seq 1 "$N"); do
  s=${SRC[$(( (i-1) % ${#SRC[@]} ))]}
  f="$TMP/diwali_${TAG}_$i.jpg"; cp "$s" "$f"; head -c 64 /dev/urandom >> "$f"
done
export URL IMMICH_API_KEY
up() { ts=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  curl -s -o /dev/null -w '%{http_code}\n' -X POST "$URL/api/assets" -H "x-api-key: $IMMICH_API_KEY" \
    -F "assetData=@$1" -F "fileCreatedAt=$ts" -F "fileModifiedAt=$ts" -F "filename=$(basename "$1")"; }
export -f up
start=$(date +%s)
ls "$TMP"/*.jpg | xargs -P "$P" -I{} bash -c 'up {}' | sort | uniq -c
echo "uploaded $N in $(( $(date +%s) - start ))s"
