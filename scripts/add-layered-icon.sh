#!/bin/bash
# Xcode 26+ compiles SVG layers; older toolchains retain the flat icon.
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?Usage: add-layered-icon.sh APP}"
xcode_major=$(xcodebuild -version 2>/dev/null | awk '/^Xcode / { split($2, v, "."); print v[1] }' || true)
if [[ "${xcode_major:-0}" -lt 26 ]] || ! xcrun --find actool >/dev/null 2>&1; then
    if [[ "${REQUIRE_LAYERED_ICON:-0}" == 1 ]]; then
        echo "Xcode 26 or later is required to build the layered release icon" >&2
        exit 1
    fi
    echo "Using the flat app icon (Xcode 26+ is not available)"
    exit 0
fi

mkdir -p .build
stage=$(mktemp -d "$PWD/.build/layered-icon.XXXXXX")
trap 'rm -rf "$stage"' EXIT
xcrun actool artwork/BatteryBar.icon --compile "$stage" \
    --output-format human-readable-text --notices --warnings \
    --output-partial-info-plist "$stage/icon-info.plist" \
    --app-icon BatteryBar --include-all-app-icons \
    --platform macosx --target-device mac --minimum-deployment-target 13.0
[[ -s "$stage/Assets.car" ]] || { echo "Layered icon compilation produced no asset catalog" >&2; exit 1; }
cp "$stage/Assets.car" "$app/Contents/Resources/Assets.car"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconName string BatteryBar' "$app/Contents/Info.plist"
shasum -a 256 artwork/BatteryBar.icon/icon.json artwork/BatteryBar.icon/Assets/*.svg > "$stage/source.sha256"
rm -rf .build/layered-icon
mv "$stage" .build/layered-icon
echo "Added the layered app icon"
