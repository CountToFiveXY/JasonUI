#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
source_app="$project_dir/.build/app-package/JasonApp.app"
installed_app="/Applications/JasonApp.app"
legacy_app="/Applications/JasonUI.app"

function pause_on_error {
    exit_code=$?
    trap - EXIT
    if (( exit_code != 0 )); then
        echo
        echo "Update failed. Review the error above."
        read "?Press Return to close…"
    fi
    exit $exit_code
}
trap pause_on_error EXIT

cd "$project_dir"

echo "Testing JasonUI…"
swift test

echo
echo "Building the app…"
"$project_dir/scripts/package_app.sh"

echo
echo "Installing JasonApp in Applications…"
osascript -e 'tell application id "com.jason.JasonUI" to quit' 2>/dev/null || true
for _ in {1..30}; do
    pgrep -x JasonUI >/dev/null || break
    sleep 0.1
done
rm -rf "$installed_app"
rm -rf "$legacy_app"
ditto "$source_app" "$installed_app"

echo
echo "JasonApp was updated successfully."
open "$installed_app"
trap - EXIT
