#!/bin/bash
# Builds Resources/AppIcon.icns from the artwork in Resources/Icon: one square PNG per pixel size (128.png, 256.png,
# and so on). Each size macOS wants comes from the artwork of that size, or is scaled down from the next larger one.
# Sizes above the largest artwork are left out, and macOS scales up for them. Run it after changing the artwork, and
# commit both.
set -euo pipefail
cd "$(dirname "$0")/.."

ART=Resources/Icon
SET="$(mktemp -d)/AppIcon.iconset"
mkdir "$SET"

# The smallest artwork at least $1 pixels wide, or nothing.
artwork_for() {
  local file
  for file in $(ls "$ART" | sort -n); do
    if (( ${file%.png} >= $1 )); then echo "$ART/$file"; return; fi
  done
}

# Each image iconutil knows, and its size in pixels (@2x is the Retina version of a size in points).
while read -r name px; do
  source="$(artwork_for "$px")"
  if [[ -z "$source" ]]; then continue; fi
  if [[ "$source" == "$ART/$px.png" ]]; then
    cp "$source" "$SET/$name.png"
  else
    sips -z "$px" "$px" "$source" --out "$SET/$name.png" >/dev/null
  fi
done <<'SIZES'
icon_16x16 16
icon_16x16@2x 32
icon_32x32 32
icon_32x32@2x 64
icon_128x128 128
icon_128x128@2x 256
icon_256x256 256
icon_256x256@2x 512
icon_512x512 512
icon_512x512@2x 1024
SIZES

iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns ($(ls "$SET" | tr '\n' ' '))"
