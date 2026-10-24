#!/bin/bash
# Installs Little Dia, a "Little Arc" for Dia: https://github.com/austindick/little-dia
#
#   curl -fsSL https://raw.githubusercontent.com/austindick/little-dia/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/austindick/little-dia/main/install.sh | bash -s -- --uninstall
#   bash install.sh path/to/Little-Dia.zip      (install a local build)
#
# Downloading with curl (rather than a browser) leaves the app without the quarantine flag, so macOS opens it without
# the "can't check this app" warning. Releases are signed with the project's own certificate, not notarized.
set -euo pipefail

RELEASE_URL="https://github.com/austindick/little-dia/releases/latest/download/Little-Dia.zip"
APPS_DIR="${LITTLEDIA_APPS_DIR:-$HOME/Applications}"
APP_SUPPORT="${LITTLEDIA_APP_SUPPORT:-$HOME/Library/Application Support}"
APP="$APPS_DIR/Little Dia.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

quit_running_app() {
  [[ -n "${LITTLEDIA_NO_OPEN:-}" ]] && return
  pkill -x LittleDia || true
  sleep 1
}

install_app() {
  local zip="${1:-}"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  if [[ -z "$zip" ]]; then
    echo "Downloading Little Dia…"
    zip="$WORK/Little-Dia.zip"
    curl -fsSL "$RELEASE_URL" -o "$zip"
  fi
  ditto -x -k "$zip" "$WORK/unpacked"
  [[ -d "$WORK/unpacked/Little Dia.app" ]] || { echo "error: $zip doesn't contain Little Dia.app" >&2; exit 1; }

  quit_running_app
  mkdir -p "$APPS_DIR"
  rm -rf "$APP"
  ditto "$WORK/unpacked/Little Dia.app" "$APP"
  [[ -n "${LITTLEDIA_NO_OPEN:-}" ]] || "$LSREGISTER" -f "$APP"
  echo "Installed $APP"

  if [[ -z "${LITTLEDIA_NO_OPEN:-}" ]]; then
    # LaunchServices sometimes refuses (-600) right after an old copy quit; wait and retry once.
    open "$APP" || { sleep 2; open "$APP"; }
  fi
  echo "Little Dia is installed. Follow the setup window to finish."
}

uninstall_app() {
  quit_running_app
  [[ -d "$APP" && -z "${LITTLEDIA_NO_OPEN:-}" ]] && "$LSREGISTER" -u "$APP" || true
  rm -rf "$APP" "$APP_SUPPORT/Little Dia"
  rm -f "$APP_SUPPORT/Dia/NativeMessagingHosts/com.austindick.littledia.bridge.json" \
        "$APP_SUPPORT/Dia/User Data/NativeMessagingHosts/com.austindick.littledia.bridge.json"
  echo "Little Dia is uninstalled. Two things to finish by hand:"
  echo "  Set Dia as your default browser: System Settings → Desktop & Dock → Default web browser."
  echo "  Remove the Little Dia extension in Dia: chrome://extensions."
}

case "${1:-}" in
  --uninstall) uninstall_app ;;
  -h|--help) echo "usage: install.sh [path/to/Little-Dia.zip | --uninstall]" ;;
  *) install_app "${1:-}" ;;
esac
