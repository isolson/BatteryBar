#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application certificate name}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile}"
[[ "$SIGNING_IDENTITY" == "Developer ID Application: "* ]] || {
    echo "A Developer ID Application certificate is required for public releases" >&2; exit 1;
}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' BatteryBar/Resources/Info.plist)
[[ -z "${RELEASE_TAG:-}" || "$RELEASE_TAG" == "v$version" ]] || {
    echo "Release tag must be v$version, got $RELEASE_TAG" >&2; exit 1;
}
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
notary_arguments=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
    notary_arguments+=(--keychain "$NOTARY_KEYCHAIN")
fi

make test
make build
mkdir -p .build dist
stage=$(mktemp -d "$PWD/.build/release.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/BatteryBar.app"
ditto BatteryBar.app "$app"
strip "$app/Contents/MacOS/BatteryBar"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$app"
codesign --verify --strict --verbose=2 "$app"

ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/submission.zip"
# --wait alone does not prove acceptance: check the service status as well.
notary_exit=0
xcrun notarytool submit "$stage/submission.zip" "${notary_arguments[@]}" \
    --wait --timeout 30m --output-format json > "$stage/notarization.json" || notary_exit=$?
status=$(plutil -extract status raw -o - "$stage/notarization.json" 2>/dev/null || true)
if [[ "$notary_exit" != 0 || "$status" != Accepted ]]; then
    submission=$(plutil -extract id raw -o - "$stage/notarization.json" 2>/dev/null || true)
    if [[ -n "$submission" ]]; then
        xcrun notarytool log "$submission" "${notary_arguments[@]}" || true
    fi
    echo "Notarization was not accepted: ${status:-no result} (exit $notary_exit)" >&2
    exit 1
fi
xcrun stapler staple "$app"
bash scripts/verify-app.sh "$app" --release

# ZIP files cannot hold a stapled ticket. Archive the app after stapling it.
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/BatteryBar.app.zip"
ditto -x -k "$stage/BatteryBar.app.zip" "$stage/extracted"
bash scripts/verify-app.sh "$stage/extracted/BatteryBar.app" --release
(
    cd "$stage"
    shasum -a 256 BatteryBar.app.zip > BatteryBar.app.zip.sha256
    shasum -a 256 -c BatteryBar.app.zip.sha256
)
# Only replace the previous output after all checks pass.
mv "$stage/BatteryBar.app.zip" "$stage/BatteryBar.app.zip.sha256" dist/
echo "Release files are ready in dist/"
