#!/bin/bash
# Stage a complete, verified bundle before replacing an existing installation.
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="${1:-BatteryBar.app}"
destination="${2:-/Applications/BatteryBar.app}"
[[ "$(basename "$destination")" == BatteryBar.app && ! -L "$destination" ]] || {
    echo "Destination must be a BatteryBar.app bundle, not a symbolic link" >&2; exit 1;
}
parent=$(cd "$(dirname "$destination")" && pwd -P)
destination="$parent/BatteryBar.app"
source_parent=$(cd "$(dirname "$source_app")" && pwd -P)
[[ "$source_parent/$(basename "$source_app")" != "$destination" ]] || {
    echo "Source and destination must be different" >&2; exit 1;
}
if [[ "${3:-}" != --locked ]]; then
    # The OS releases this lock even if an installer exits unexpectedly. Keep the
    # empty lock file so competing installers always lock the same file.
    exec /usr/bin/lockf -k -t 0 "$parent/.BatteryBar-install.lock" \
        /bin/bash "$PWD/scripts/install.sh" "$source_app" "$destination" --locked
fi
bash scripts/verify-app.sh "$source_app"
if [[ -e "$destination" ]]; then
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")
    expected=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' BatteryBar/Resources/Info.plist)
    [[ "$identifier" == "$expected" ]] || { echo "Destination belongs to another app" >&2; exit 1; }
fi

check_not_running() {
    local processes executable
    processes=$(/bin/ps -axo comm=) || { echo "Cannot check running apps" >&2; exit 1; }
    while IFS= read -r executable; do
        if [[ "$executable" == "$destination/Contents/MacOS/BatteryBar" ]]; then
            echo "Quit the installed BatteryBar, then run make install again" >&2
            exit 1
        fi
    done <<< "$processes"
}
check_not_running
stage=$(mktemp -d "$parent/.BatteryBar-install.XXXXXX")
previous="$stage/previous.app"
cleanup() {
    # Restore the previous bundle if replacement did not complete.
    if [[ -e "$previous" && ! -e "$destination" ]]; then
        mv "$previous" "$destination" || {
            echo "Previous app is preserved at $previous" >&2
            return
        }
    fi
    rm -rf "$stage"
}
trap cleanup EXIT
ditto "$source_app" "$stage/BatteryBar.app"
bash scripts/verify-app.sh "$stage/BatteryBar.app"
check_not_running
if [[ -e "$destination" ]]; then mv "$destination" "$previous"; fi
mv "$stage/BatteryBar.app" "$destination"
echo "Installed to $destination"
