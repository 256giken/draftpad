#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SET=$TMP/AppIcon.iconset
mkdir "$SET"
for s in 16 32 128 256 512; do
  rsvg-convert -w $s -h $s assets/icon.svg -o "$SET/icon_${s}x${s}.png"
  rsvg-convert -w $((s * 2)) -h $((s * 2)) assets/icon.svg -o "$SET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$SET" -o assets/AppIcon.icns
