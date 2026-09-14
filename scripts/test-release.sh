#!/bin/bash
# Run after make build. These checks do not contact Apple's notary service.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
stage=$(mktemp -d "$PWD/.build/package-test.XXXXXX")
trap 'rm -rf "$stage"' EXIT

expect_failure() {
    if "$@" > "$stage/failure.log" 2>&1; then
        echo "Expected this check to fail: $*" >&2
        cat "$stage/failure.log" >&2
        exit 1
    fi
}

bash scripts/verify-app.sh BatteryBar.app
ditto -c -k --sequesterRsrc --keepParent BatteryBar.app "$stage/BatteryBar.app.zip"
ditto -x -k "$stage/BatteryBar.app.zip" "$stage/extracted"
app="$stage/extracted/BatteryBar.app"
bash scripts/verify-app.sh "$app"
(
    cd "$stage"
    shasum -a 256 BatteryBar.app.zip > BatteryBar.app.zip.sha256
    shasum -a 256 -c BatteryBar.app.zip.sha256
)
expect_failure bash scripts/verify-app.sh "$app" --release
expect_failure env RELEASE_TAG=v0.0.0 bash scripts/verify-app.sh "$app"
expect_failure env -u SIGNING_IDENTITY -u NOTARY_PROFILE bash scripts/release.sh
expect_failure env SIGNING_IDENTITY=- NOTARY_PROFILE=unused bash scripts/release.sh
expect_failure env SIGNING_IDENTITY='Developer ID Application: Test' NOTARY_PROFILE=unused \
    RELEASE_TAG=v0.0.0 bash scripts/release.sh

# The metadata and signature checks must both detect damaged bundles.
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 999' "$app/Contents/Info.plist"
expect_failure bash scripts/verify-app.sh "$app"
ditto BatteryBar.app "$app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Changed' "$app/Contents/Info.plist"
expect_failure bash scripts/verify-app.sh "$app"
ditto BatteryBar.app "$app"
rm "$app/Contents/Resources/BatteryBar.icns"
codesign --force --sign - "$app"
expect_failure bash scripts/verify-app.sh "$app"
if [[ -f BatteryBar.app/Contents/Resources/Assets.car ]]; then
    ditto BatteryBar.app "$app"
    rm "$app/Contents/Resources/Assets.car"
    codesign --force --sign - "$app"
    expect_failure bash scripts/verify-app.sh "$app"
fi
echo "Packaging, metadata, signature, and release safeguard tests passed."
