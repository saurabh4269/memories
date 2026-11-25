#!/usr/bin/env bash
# Rebuild the Memories Android app on the Azure build VM and publish the APK to GitHub Releases.
#
#   scripts/release_app.sh                 # build + upload to the default release tag
#   SKIP_UPLOAD=1 scripts/release_app.sh   # build + fetch only
#   TAG=v0.1.1 scripts/release_app.sh      # upload to another (existing or new) release
#
# Steps:
#   1. snapshot mobile/ native/ open-api/ i18n/ from the source tree (so concurrent edits don't race the upload)
#   2. rsync the snapshot to the VM and into /opt/appbuild/immich/<dir> (other upstream files stay as they are)
#   3. run /opt/appbuild/build.sh on the VM. Its build-inner.sh patches the VM copy only:
#      applicationId ai.memories.festive, label Memories, arm64 + x64, upload key signing.
#   4. fetch memories-release.apk / .aab into knowledge-dump/apk/
#   5. gh release upload --clobber (creates the release first if it does not exist)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${SRC:-$ROOT/knowledge-dump/repos/immich-mobile-try}"
OUT="${OUT:-$ROOT/knowledge-dump/apk}"
VM="${VM:-azureuser@74.225.200.30}"
KEY="${KEY:-$HOME/.ssh/memories_azure}"
TAG="${TAG:-v0.1.0-festive-hacks}"
REPO="${REPO:-saurabh4269/memories}"
DIRS=(mobile native open-api i18n)

SSH=(ssh -i "$KEY" -o ConnectTimeout=20 -o ServerAliveInterval=30)
retry() { local n=0; until "$@"; do n=$((n + 1)); [[ $n -ge 4 ]] && return 1; echo "retry $n: $*" >&2; sleep 5; done; }

for d in "${DIRS[@]}"; do [[ -d "$SRC/$d" ]] || { echo "missing $SRC/$d" >&2; exit 1; }; done

EXCLUDES=(--exclude='build/' --exclude='.dart_tool/' --exclude='.gradle/' --exclude='ios/'
  --exclude='Pods/' --exclude='target/' --exclude='node_modules/' --exclude='.DS_Store'
  --exclude='*.jks' --exclude='key.properties' --exclude='local.properties')

SNAP="$(mktemp -d "${TMPDIR:-/tmp}/memories-release.XXXXXX")"
trap 'rm -rf "$SNAP"' EXIT
echo "== snapshot $SRC -> $SNAP"
for d in "${DIRS[@]}"; do rsync -a "${EXCLUDES[@]}" "$SRC/$d" "$SNAP/"; done
grep -m1 '^version:' "$SNAP/mobile/pubspec.yaml"

echo "== rsync to $VM:/opt/appbuild/staging"
retry rsync -az --delete -e "${SSH[*]}" "$SNAP/" "$VM:/opt/appbuild/staging/"

echo "== build on VM (log: /opt/appbuild/build.log)"
retry "${SSH[@]}" "$VM" 'set -e; cd /opt/appbuild
  for d in mobile native open-api i18n; do
    rsync -a --delete --exclude /build/ --exclude /.dart_tool/ --exclude /android/.gradle/ \
      --exclude /android/key.jks --exclude /target/ --exclude /node_modules/ staging/$d/ immich/$d/
  done
  # Our fork trims rust-toolchain.toml targets for local dev; the build hooks also need the
  # Android x86_64 and Linux host targets. Patch the VM copy only.
  printf "%s\n" "[toolchain]" "channel = \"1.99.1\"" \
    "targets = [\"aarch64-linux-android\", \"x86_64-linux-android\", \"aarch64-apple-darwin\", \"x86_64-unknown-linux-gnu\"]" \
    > immich/native/crates/native_core_ffi/rust-toolchain.toml
  [ -f build.log ] && mv -f build.log build.log.prev
  nohup /opt/appbuild/build.sh > build.log 2>&1 < /dev/null &
  echo started'

# Poll instead of holding one long ssh session (the VM link resets now and then).
while true; do
  sleep 30
  status="$("${SSH[@]}" "$VM" 'if pgrep -f "[b]uild-inner[.]sh" >/dev/null; then echo RUNNING; elif grep -q "SUCCESS in" /opt/appbuild/build.log; then echo SUCCESS; else echo FAILED; fi' 2>/dev/null || echo UNKNOWN)"
  case "$status" in
    RUNNING|UNKNOWN) "${SSH[@]}" "$VM" 'tail -n 1 /opt/appbuild/build.log' 2>/dev/null || true ;;
    SUCCESS) "${SSH[@]}" "$VM" 'tail -n 4 /opt/appbuild/build.log'; break ;;
    FAILED) echo "build failed; last lines:" >&2; "${SSH[@]}" "$VM" 'tail -n 40 /opt/appbuild/build.log' >&2; exit 1 ;;
  esac
done

echo "== fetch artifacts -> $OUT"
mkdir -p "$OUT"
retry rsync -az -e "${SSH[*]}" "$VM:/opt/appbuild/out/memories-release.apk" "$VM:/opt/appbuild/out/memories-release.aab" "$OUT/"
ls -lh "$OUT/memories-release.apk" "$OUT/memories-release.aab"

if [[ "${SKIP_UPLOAD:-0}" == 1 ]]; then
  echo "SKIP_UPLOAD=1, not touching GitHub"
  exit 0
fi

echo "== GitHub release $TAG on $REPO"
cd "$ROOT"
if ! gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  gh release create "$TAG" -R "$REPO" --title "Memories ($TAG)" --notes "Android build of the Memories app. Fork of Immich (AGPL-3.0)."
fi
# gh "file#label" only sets a display label, so copy to the asset filename we want in the URL.
cp "$OUT/memories-release.apk" "$SNAP/memories-0.1.0.apk"
gh release upload "$TAG" -R "$REPO" --clobber "$SNAP/memories-0.1.0.apk#Memories Android APK (arm64 + x86_64)"
echo "APK: https://github.com/$REPO/releases/download/$TAG/memories-0.1.0.apk"
echo "AAB for Play internal testing: $OUT/memories-release.aab (upload by hand in Play Console)"
