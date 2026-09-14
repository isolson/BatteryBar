#!/bin/bash
# Build the macOS icon from the tracked PNG with Apple's command-line tools.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?Usage: build-icon.sh OUTPUT.icns}"
stage=$(mktemp -d "${TMPDIR:-/tmp}/batterybar-icon.XXXXXX")
trap 'rm -rf "$stage"' EXIT
iconset="$stage/BatteryBar.iconset"
mkdir -p "$iconset" "$(dirname "$output")"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" artwork/AppIcon.png --out "$iconset/icon_${size}x${size}.png" > /dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" artwork/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil --convert icns "$iconset" --output "$stage/BatteryBar.icns"
mv "$stage/BatteryBar.icns" "$output"
