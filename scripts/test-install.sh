#!/bin/bash
# Exercises install.sh against a fake release zip in a temp folder: install, then uninstall. Never touches the real
# ~/Applications or ~/Library (the LITTLEDIA_* variables point everything at the temp folder).
set -euo pipefail
cd "$(dirname "$0")/.."

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "test-install: FAIL: $*" >&2; exit 1; }
export LITTLEDIA_NO_OPEN=1 LITTLEDIA_APPS_DIR="$T/apps" LITTLEDIA_APP_SUPPORT="$T/support"

mkdir -p "$T/build/Little Dia.app/Contents"
echo '<plist version="1.0"><dict/></plist>' > "$T/build/Little Dia.app/Contents/Info.plist"
ditto -c -k --keepParent "$T/build/Little Dia.app" "$T/fake.zip"

bash install.sh "$T/fake.zip" > "$T/install.out" || fail "install exited non-zero"
[[ -f "$T/apps/Little Dia.app/Contents/Info.plist" ]] || fail "app not installed"
grep -q "Little Dia is installed" "$T/install.out" || fail "no success message"

mkdir -p "$T/support/Little Dia" "$T/support/Dia/NativeMessagingHosts" "$T/support/Dia/User Data/NativeMessagingHosts"
touch "$T/support/Dia/NativeMessagingHosts/com.austindick.littledia.bridge.json" \
      "$T/support/Dia/User Data/NativeMessagingHosts/com.austindick.littledia.bridge.json" \
      "$T/support/Dia/NativeMessagingHosts/other.host.json"
bash install.sh --uninstall > "$T/uninstall.out" || fail "uninstall exited non-zero"
[[ ! -e "$T/apps/Little Dia.app" ]] || fail "app still there"
[[ ! -e "$T/support/Little Dia" ]] || fail "support folder still there"
[[ ! -e "$T/support/Dia/NativeMessagingHosts/com.austindick.littledia.bridge.json" ]] || fail "bridge manifest still there"
[[ ! -e "$T/support/Dia/User Data/NativeMessagingHosts/com.austindick.littledia.bridge.json" ]] || fail "User Data bridge manifest still there"
[[ -e "$T/support/Dia/NativeMessagingHosts/other.host.json" ]] || fail "removed another app's manifest"
grep -q "Desktop & Dock" "$T/uninstall.out" || fail "no default-browser instruction"
grep -q "chrome://extensions" "$T/uninstall.out" || fail "no extension instruction"

echo "test-install: OK"
