#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
app="${1:?Usage: verify-app.sh APP [--release]}"
mode="${2:-}"
[[ -z "$mode" || "$mode" == --release ]] || { echo "Unknown verification mode: $mode" >&2; exit 1; }
plist="$app/Contents/Info.plist"
template=BatteryBar/Resources/Info.plist
binary="$app/Contents/MacOS/BatteryBar"

plutil -lint "$plist"
for key in CFBundleIdentifier CFBundleExecutable CFBundleIconFile CFBundlePackageType CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion LSUIElement; do
    actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")
    expected=$(/usr/libexec/PlistBuddy -c "Print :$key" "$template")
    [[ "$actual" == "$expected" ]] || { echo "Incorrect bundle value: $key" >&2; exit 1; }
done
icon_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist")
icon="$app/Contents/Resources/$icon_name"
[[ -s "$icon" ]] || { echo "App icon is missing or empty" >&2; exit 1; }
icon_check=$(mktemp -d "${TMPDIR:-/tmp}/batterybar-icon-check.XXXXXX")
trap 'rm -rf "$icon_check"' EXIT
iconutil --convert iconset "$icon" --output "$icon_check/BatteryBar.iconset"
for size in 16 32 128 256 512; do
    for suffix in '' '@2x'; do
        [[ -s "$icon_check/BatteryBar.iconset/icon_${size}x${size}${suffix}.png" ]] || {
            echo "App icon is missing the ${size}x${size}${suffix} representation" >&2; exit 1;
        }
    done
done
icon_catalog="$app/Contents/Resources/Assets.car"
icon_asset=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$plist" 2>/dev/null || true)
if [[ -e "$icon_catalog" || -n "$icon_asset" || "$mode" == --release || "${REQUIRE_LAYERED_ICON:-0}" == 1 ]]; then
    [[ -s "$icon_catalog" && "$icon_asset" == BatteryBar ]] || {
        echo "Layered icon asset catalog or bundle metadata is missing" >&2; exit 1;
    }
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
[[ -z "${RELEASE_TAG:-}" || "$RELEASE_TAG" == "v$version" ]] || {
    echo "Release tag must be v$version, got $RELEASE_TAG" >&2; exit 1;
}
[[ -x "$binary" ]] || { echo "App executable is missing or not executable" >&2; exit 1; }
[[ "$(lipo -archs "$binary")" == arm64 ]] || { echo "Expected an Apple Silicon executable" >&2; exit 1; }
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")
binary_minimum=$(xcrun vtool -show-build "$binary" | awk '$1 == "minos" { print $2 }')
[[ "$binary_minimum" == "$minimum" ]] || { echo "Executable deployment target does not match the bundle" >&2; exit 1; }
codesign --verify --strict --verbose=2 "$app"

if [[ "$mode" == --release ]]; then
    signature=$(codesign --display --verbose=4 "$app" 2>&1)
    [[ "$signature" == *"Authority=Developer ID Application:"* ]] || { echo "Developer ID Application signature required" >&2; exit 1; }
    [[ "$signature" == *"runtime"* && "$signature" == *"Timestamp="* ]] || { echo "Hardened runtime and secure timestamp required" >&2; exit 1; }
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi
echo "Verified $app ($version, arm64, macOS $minimum+)"
