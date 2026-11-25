#!/usr/bin/env bash
# Sync the Memories fork of the Immich Flutter app into ./app (committed copy).
# Source of truth while hacking: knowledge-dump/repos/immich-mobile-try (gitignored).
#
# Layout (keeps the relative path deps in pubspec.yaml working):
#   app/mobile  <- immich-mobile-try/mobile   (Flutter app)
#   app/native  <- immich-mobile-try/native   (native_core Rust/FFI path dependency: ../native/native_core)
#   app/LICENSE <- immich-app/immich LICENSE  (AGPL-3.0)
#   app/NOTICE.md (fork notice; created once, never overwritten)
#
# Safe to rerun; uses --delete so removed files disappear from app/ too.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${SRC:-$ROOT/knowledge-dump/repos/immich-mobile-try}"
UPSTREAM="${UPSTREAM:-$ROOT/knowledge-dump/repos/immich}"
DEST="$ROOT/app"

[[ -d "$SRC/mobile" ]] || { echo "source not found: $SRC/mobile" >&2; exit 1; }
mkdir -p "$DEST/mobile" "$DEST/native"

EXCLUDES=(
  --exclude='build/' --exclude='.dart_tool/' --exclude='.gradle/' --exclude='.kotlin/'
  --exclude='.idea/' --exclude='*.iml' --exclude='.fvm/' --exclude='.cxx/'
  --exclude='ios/Pods/' --exclude='ios/.symlinks/' --exclude='ios/Flutter/ephemeral/'
  --exclude='ios/Flutter/Generated.xcconfig' --exclude='ios/Flutter/flutter_export_environment.sh'
  --exclude='.flutter-plugins' --exclude='.flutter-plugins-dependencies'
  --exclude='local.properties' --exclude='key.properties' --exclude='*.jks' --exclude='*.keystore'
  --exclude='*.apk' --exclude='*.aab' --exclude='*.ipa'
  --exclude='target/' --exclude='.env' --exclude='*.env' --exclude='.DS_Store'
  --exclude='android/fastlane/' --exclude='android/metadata/'   # store listings/screenshots (~43 MB), not needed to build
  --exclude='coverage/'
)

rsync -a --delete "${EXCLUDES[@]}" "$SRC/mobile/" "$DEST/mobile/"
rsync -a --delete "${EXCLUDES[@]}" "$SRC/native/" "$DEST/native/"

if [[ -f "$UPSTREAM/LICENSE" ]]; then
  cp "$UPSTREAM/LICENSE" "$DEST/LICENSE"
elif [[ -f "$SRC/LICENSE" ]]; then
  cp "$SRC/LICENSE" "$DEST/LICENSE"
else
  echo "WARNING: Immich LICENSE not found; app/LICENSE not updated" >&2
fi

if [[ ! -f "$DEST/NOTICE.md" ]]; then
  cat > "$DEST/NOTICE.md" <<'NOTICE'
# NOTICE

The code in this directory is a modified fork of the **Immich mobile app**
(<https://github.com/immich-app/immich>, `mobile/` and `native/` directories),
taken at upstream commit **`eb97880`** (`feat(server): app login code exchange (#33599)`).

Immich is Copyright (c) Immich contributors and is licensed under the
**GNU Affero General Public License v3.0** (see [`LICENSE`](LICENSE)).
This fork is distributed under the same licence. Excluded from this copy:
build outputs, caches, `native/target`, and the Play Store listing assets
(`android/fastlane`, `android/metadata`).

## Changes made for Memories

<!-- TODO: list our changes (files / features), e.g.: -->
- TODO: Memories tab / reel prompt UI
- TODO: call to the Memories director API
- TODO: Flagsmith feature flags in the app
- TODO: branding / app id changes
NOTICE
fi

echo "synced -> $DEST"
du -sh "$DEST"
