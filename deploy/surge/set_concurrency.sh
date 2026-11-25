#!/usr/bin/env bash
# Runs ON THE VM. Usage: set_concurrency.sh <faceDetection> <smartSearch>
set -euo pipefail; source ~/.immich_key; H="x-api-key: $IMMICH_API_KEY"; U=http://127.0.0.1:2283
curl -s $U/api/system-config -H "$H" | jq --argjson f "$1" --argjson s "$2" '.job.faceDetection.concurrency=$f | .job.smartSearch.concurrency=$s' \
 | curl -s -X PUT $U/api/system-config -H "$H" -H "content-type: application/json" -d @- | jq -c '{face:.job.faceDetection, smart:.job.smartSearch}'
