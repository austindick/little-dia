#!/bin/bash
# Builds "build/Little Dia.app". With --install, replaces "~/Applications/Little Dia.app", registers it with
# LaunchServices and launches it.
#
# Signing: set LITTLEDIA_SIGN_IDENTITY to a stable code-signing identity (a self-signed one is fine; releases use
# "Little Dia"). With the default ad-hoc signature ("-"), macOS treats every build as a new app, so the Accessibility
# permission has to be granted again after each rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${LITTLEDIA_SIGN_IDENTITY:--}"
APP="build/Little Dia.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Universal (Apple silicon and Intel) when the toolchain can; otherwise this Mac's architecture only.
ARCHS=(--arch arm64 --arch x86_64)
if ! swift build -c release "${ARCHS[@]}" --product LittleDia || ! swift build -c release "${ARCHS[@]}" --product littledia-host; then
  echo "warning: universal build failed; building for this Mac's architecture only" >&2
  ARCHS=()
  swift build -c release --product LittleDia
  swift build -c release --product littledia-host
fi
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp "$BIN/LittleDia" "$APP/Contents/MacOS/LittleDia"
cp "$BIN/littledia-host" "$APP/Contents/Helpers/littledia-host"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The extension ships inside the app (sealed by its signature); the app copies it to where Dia loads it from.
mkdir -p "$APP/Contents/Resources"
ditto Extension "$APP/Contents/Resources/Extension"
rm -rf "$APP/Contents/Resources/Extension/test"

if [[ "$IDENTITY" == "-" ]]; then
  echo "warning: ad-hoc signing; Accessibility access must be re-granted after every build (set LITTLEDIA_SIGN_IDENTITY)" >&2
fi
codesign --force --sign "$IDENTITY" --identifier com.austindick.littledia.host "$APP/Contents/Helpers/littledia-host"
codesign --force --sign "$IDENTITY" "$APP"
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/Little Dia.app"
  pkill -x LittleDia || true
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  "$LSREGISTER" -f "$DEST"
  # LaunchServices sometimes refuses (-600) right after the old copy quit; wait and retry once.
  sleep 1
  open "$DEST" || { sleep 2; open "$DEST"; }
  echo "installed and launched $DEST"
fi
