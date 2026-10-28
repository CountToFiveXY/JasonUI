#!/bin/zsh
# Use the selected Apple toolchain and probe SDK compatibility before building.
set -euo pipefail

project_dir=${0:A:h:h}

if [[ "$(uname -s)" != "Darwin" ]]; then
    print -u2 "JasonUI requires macOS 14 or newer."
    exit 1
fi

if ! xcrun --find swift >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
    print -u2 "Install Xcode Command Line Tools with: xcode-select --install"
    print -u2 "If Xcode is installed, select its developer directory and accept its licence."
    exit 1
fi

default_sdk=$(xcrun --sdk macosx --show-sdk-path)
sdk_dir=${default_sdk:h}
sdk_candidates=("$default_sdk" "$sdk_dir"/MacOSX*.sdk(NnOn))
if [[ -n "${JASONUI_SWIFT_SDK:-}" ]]; then
    # An explicit choice must succeed on its own, rather than silently falling back.
    if [[ ! -d "$JASONUI_SWIFT_SDK" ]]; then
        print -u2 "JASONUI_SWIFT_SDK is not an SDK directory: $JASONUI_SWIFT_SDK"
        exit 1
    fi
    sdk_candidates=("$JASONUI_SWIFT_SDK")
fi

probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/jasonui-sdk.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
cat > "$probe_dir/Compatibility.swift" <<'EOF'
import SwiftUI
import Observation

@Observable final class CompatibilityModel {
    var value = false
}

struct CompatibilityView: View {
    @State private var model = CompatibilityModel()
    var body: some View { Text(model.value ? "Yes" : "No") }
}
EOF

typeset -A checked_sdks
selected_sdk=""
for candidate in "${sdk_candidates[@]}"; do
    [[ -d "$candidate" ]] || continue
    # Resolve aliases so MacOSX.sdk and versioned symlinks are only checked once.
    sdk=${candidate:A}
    [[ -z "${checked_sdks[$sdk]-}" ]] || continue
    checked_sdks[$sdk]=1
    print -u2 "Checking ${sdk:t} with the selected Swift compiler..."
    if xcrun swiftc -typecheck -swift-version 6 \
        -target "$(uname -m)-apple-macos14.0" -sdk "$sdk" \
        "$probe_dir/Compatibility.swift" > "$probe_dir/probe.log" 2>&1; then
        selected_sdk="$sdk"
        break
    fi
    print -u2 "SDK ${sdk:t} is incompatible with the selected Swift compiler."
done

if [[ -z "$selected_sdk" ]]; then
    [[ ! -f "$probe_dir/probe.log" ]] || cat "$probe_dir/probe.log" >&2
    print -u2 "No compatible macOS SDK was found. JasonUI needs Swift 6 or newer with SwiftUI and Observation support."
    print -u2 "Install/update Xcode or Command Line Tools, or select another installed Xcode with DEVELOPER_DIR."
    print -u2 "To choose an SDK explicitly, set JASONUI_SWIFT_SDK to its directory."
    exit 1
fi

print -u2 "Building local sources with ${selected_sdk:t}."
cd "$project_dir"
xcrun swift build --sdk "$selected_sdk" "$@"
