#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
build_dir="$project_dir/.build/app-package"
app_dir="$build_dir/JasonApp.app"
iconset_dir="$build_dir/AppIcon.iconset"
source_icon="$project_dir/Resources/AppIcon.png"
github_icon="$project_dir/Sources/JasonUI/Resources/GitHubMark.png"
galaxy_brand="$project_dir/Sources/JasonUI/Resources/GalaxyArcherBrand.png"

cd "$project_dir"
swift build -c release

rm -rf "$build_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$iconset_dir"
cp "$project_dir/.build/release/JasonUI" "$app_dir/Contents/MacOS/JasonUI"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$github_icon" "$app_dir/Contents/Resources/GitHubMark.png"
cp "$galaxy_brand" "$app_dir/Contents/Resources/GalaxyArcherBrand.png"
source_commit=$(git -C "$project_dir" rev-parse HEAD 2>/dev/null || echo development)
plutil -replace JasonSourceCommit -string "$source_commit" "$app_dir/Contents/Info.plist"

sips -z 16 16 "$source_icon" --out "$iconset_dir/icon_16x16.png" >/dev/null
sips -z 32 32 "$source_icon" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$source_icon" --out "$iconset_dir/icon_32x32.png" >/dev/null
sips -z 64 64 "$source_icon" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$source_icon" --out "$iconset_dir/icon_128x128.png" >/dev/null
sips -z 256 256 "$source_icon" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$source_icon" --out "$iconset_dir/icon_256x256.png" >/dev/null
sips -z 512 512 "$source_icon" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$source_icon" --out "$iconset_dir/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$source_icon" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
