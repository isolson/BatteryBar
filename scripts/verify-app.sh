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
for key in CFBundleIdentifier CFBundleExecutable CFBundlePackageType CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion LSUIElement; do
    actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")
    expected=$(/usr/libexec/PlistBuddy -c "Print :$key" "$template")
    [[ "$actual" == "$expected" ]] || { echo "Incorrect bundle value: $key" >&2; exit 1; }
done
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
