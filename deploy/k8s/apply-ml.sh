#!/usr/bin/env bash
# Render and apply the Immich ML manifest on the VM. Usage: deploy/k8s/apply-ml.sh [IMMICH_VERSION]
set -euo pipefail; cd "$(dirname "$0")/.."
V=${1:-$(./vm.sh "grep ^IMMICH_VERSION= /opt/immich/.env | cut -d= -f2")}
sed "s/__IMMICH_VERSION__/$V/; s#__CACHE_PATH__#/opt/immich-ml-cache#" k8s/immich-ml.yaml | ./vm.sh 'kubectl apply -f -'
