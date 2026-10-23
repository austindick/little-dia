#!/bin/bash
# Builds build/LilBrowWow.app. With --install, replaces ~/Applications/LilBrowWow.app, registers it with
# LaunchServices and launches it.
#
# Signing: set LILBROW_SIGN_IDENTITY to a stable code-signing identity (a self-signed one is fine).
# With the default ad-hoc signature ("-"), macOS treats every build as a new app, so the Accessibility
# permission has to be granted again after each rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${LILBROW_SIGN_IDENTITY:--}"
APP=build/LilBrowWow.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

swift build -c release --product LilBrowWow
swift build -c release --product lilbrow-host
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp "$BIN/LilBrowWow" "$APP/Contents/MacOS/LilBrowWow"
cp "$BIN/lilbrow-host" "$APP/Contents/Helpers/lilbrow-host"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ "$IDENTITY" == "-" ]]; then
  echo "warning: ad-hoc signing; Accessibility access must be re-granted after every build (set LILBROW_SIGN_IDENTITY)" >&2
fi
codesign --force --sign "$IDENTITY" "$APP/Contents/Helpers/lilbrow-host"
codesign --force --sign "$IDENTITY" "$APP"
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/LilBrowWow.app"
  pkill -x LilBrowWow || true
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  "$LSREGISTER" -f "$DEST"
  # LaunchServices sometimes refuses (-600) right after the old copy quit; wait and retry once.
  sleep 1
  open "$DEST" || { sleep 2; open "$DEST"; }
  echo "installed and launched $DEST"
fi
