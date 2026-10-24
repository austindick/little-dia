#!/bin/bash
# Builds, signs and zips Little Dia, then publishes it as a GitHub release (v<version>, with Little-Dia.zip attached),
# which is what install.sh and the app's updater download.
#
#   scripts/release.sh            build and publish (on main, clean tree)
#   scripts/release.sh --dry-run  build and zip only
#
# The version comes from Resources/Info.plist and must match Extension/manifest.json. Signing uses the "Little Dia"
# certificate: every release must be signed with it, or users would have to grant Accessibility again.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=""
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
EXTENSION_VERSION="$(/usr/bin/python3 -c 'import json; print(json.load(open("Extension/manifest.json"))["version"])')"
if [[ "$VERSION" != "$EXTENSION_VERSION" ]]; then
  echo "error: Info.plist says $VERSION but Extension/manifest.json says $EXTENSION_VERSION" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: the working tree isn't clean; commit first" >&2
  exit 1
fi
if [[ -z "$DRY_RUN" && "$(git branch --show-current)" != "main" ]]; then
  echo "error: releases are made from main" >&2
  exit 1
fi

LITTLEDIA_SIGN_IDENTITY="Little Dia" scripts/build-app.sh
rm -f build/Little-Dia.zip
ditto -c -k --keepParent "build/Little Dia.app" build/Little-Dia.zip
echo "built build/Little-Dia.zip (Little Dia $VERSION)"

if [[ -z "$DRY_RUN" ]]; then
  gh release create "v$VERSION" build/Little-Dia.zip --title "Little Dia $VERSION" --generate-notes
fi
