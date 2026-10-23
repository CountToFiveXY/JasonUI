#!/bin/zsh
# Build JasonApp from this checkout, including uncommitted changes, and open it.
# /Applications/JasonApp.app is left alone. Start or restart the backend from
# the app's Server pane, which runs JasonPython/scripts/run_local.sh.
set -euo pipefail

project_dir=${0:A:h:h}
app_dir="$project_dir/.build/app-package/JasonApp.app"
bundle_id=$(plutil -extract CFBundleIdentifier raw "$project_dir/Resources/Info.plist")

"$project_dir/scripts/package_app.sh"

# Quit any running JasonApp, installed or local, so `open` launches this build
# instead of bringing the old one forward. The backend keeps running.
if pgrep -xq JasonUI; then
    echo "Quitting the running JasonApp..."
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -xq JasonUI || break
        sleep 0.5
    done
    if pgrep -xq JasonUI; then
        echo "JasonApp did not quit. Quit it, then run this script again." >&2
        exit 1
    fi
fi

open "$app_dir"
echo "Opened $app_dir ($(git -C "$project_dir" rev-parse --short HEAD 2>/dev/null || echo development))"
