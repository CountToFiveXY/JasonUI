#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
source_app="$project_dir/.build/app-package/JasonApp.app"
installed_app="/Applications/JasonApp.app"
staged_app="/Applications/.JasonApp-install-$$.app"
backend_dir="${JASONPYTHON_PATH:-${project_dir:h}/JasonPython}"
backup_dir=""

function pause_on_error {
    exit_code=$?
    trap - EXIT
    if (( exit_code != 0 )); then
        echo
        echo "JasonApp installation failed. Review the error and tutorial above."
        read "?Press Return to close…"
    fi
    exit $exit_code
}
trap pause_on_error EXIT

function show_xcode_tutorial {
    echo
    echo "Xcode is required to build JasonApp."
    echo "1. Install Xcode from the Mac App Store."
    echo "2. Open Xcode once and allow it to install required components."
    echo "3. In Terminal, run:"
    echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "   sudo xcodebuild -license accept"
    echo "4. Run Install JasonApp.command again."
}

function choose_backend_directory {
    selected_path=$(osascript <<'APPLESCRIPT'
try
    set selectedFolder to choose folder with prompt "Choose the downloaded JasonPython repository"
    return POSIX path of selectedFolder
on error number -128
    return ""
end try
APPLESCRIPT
    )
    if [[ -n "$selected_path" ]]; then
        backend_dir="${selected_path%/}"
    fi
}

echo "JasonApp Installer"
echo "=================="
echo

if [[ ! -d /Applications/Xcode.app ]] || \
   [[ "$(xcode-select -p 2>/dev/null || true)" != "/Applications/Xcode.app/Contents/Developer" ]]; then
    show_xcode_tutorial
    exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1 || ! xcrun swift --version >/dev/null 2>&1; then
    show_xcode_tutorial
    exit 1
fi

if [[ ! -x "$backend_dir/scripts/run_local.sh" ]]; then
    echo "JasonPython was not found next to JasonUI."
    choose_backend_directory
fi

if [[ ! -x "$backend_dir/scripts/run_local.sh" ]]; then
    echo
    echo "A valid JasonPython repository is required."
    echo "Download both repositories into the same parent folder:"
    echo "  Your Folder/JasonUI"
    echo "  Your Folder/JasonPython"
    echo
    echo "The JasonPython folder must contain scripts/run_local.sh."
    exit 1
fi

cd "$project_dir"
echo "Using backend: $backend_dir"
echo
echo "Testing JasonUI…"
if ! swift test; then
    show_xcode_tutorial
    exit 1
fi

echo
echo "Building JasonApp…"
"$project_dir/scripts/package_app.sh"
codesign --verify --deep --strict "$source_app"

echo
echo "Installing JasonApp in Applications…"
osascript -e 'tell application id "com.jason.JasonUI" to quit' 2>/dev/null || true
for _ in {1..30}; do
    pgrep -x JasonUI >/dev/null || break
    sleep 0.1
done

rm -rf "$staged_app"
ditto "$source_app" "$staged_app"
codesign --verify --deep --strict "$staged_app"

if [[ -e "$installed_app" ]]; then
    backup_dir=$(mktemp -d /private/tmp/JasonApp-install-backup.XXXXXX)
    mv "$installed_app" "$backup_dir/JasonApp.app"
fi

if ! mv "$staged_app" "$installed_app"; then
    if [[ -n "$backup_dir" ]] && [[ -e "$backup_dir/JasonApp.app" ]]; then
        mv "$backup_dir/JasonApp.app" "$installed_app"
    fi
    exit 1
fi

codesign --verify --deep --strict "$installed_app"
defaults write com.jason.JasonUI backendDirectory "$backend_dir"
defaults write com.jason.JasonUI frontendDirectory "$project_dir"
saved_server=$(defaults read com.jason.JasonUI serverAddress 2>/dev/null || true)
if [[ -z "$saved_server" ]] || [[ "$saved_server" == "http://127.0.0.1:8080" ]]; then
    defaults write com.jason.JasonUI serverAddress "http://127.0.0.1:8000"
fi

if [[ -n "$backup_dir" ]]; then
    rm -rf "$backup_dir"
fi

echo
echo "JasonApp was installed successfully."
echo "Location: $installed_app"
echo
echo "Open JasonApp from Applications, then click Activate All Services."
open -R "$installed_app"
trap - EXIT
