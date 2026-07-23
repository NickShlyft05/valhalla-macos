#!/bin/zsh

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_dir/.build"
dist_dir="$project_dir/dist"
app_dir="$dist_dir/Valhalla.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
native_arch="$(uname -m)"

cd "$project_dir"
swift build -c release
native_bin="$(swift build -c release --show-bin-path)/Valhalla"

if [[ "$native_arch" == "arm64" ]]; then
  cross_arch="x86_64"
else
  cross_arch="arm64"
fi

cross_build_dir="$project_dir/.build-$cross_arch"
cross_triple="$cross_arch-apple-macosx13.0"
swift build -c release --triple "$cross_triple" --scratch-path "$cross_build_dir"
cross_bin="$cross_build_dir/$cross_arch-apple-macosx/release/Valhalla"

mkdir -p "$macos_dir" "$resources_dir"
lipo -create "$native_bin" "$cross_bin" -output "$macos_dir/Valhalla"

mkdir -p "$contents_dir"
plutil -create xml1 "$contents_dir/Info.plist"
plutil -insert CFBundleName -string "Valhalla" "$contents_dir/Info.plist"
plutil -insert CFBundleDisplayName -string "Valhalla" "$contents_dir/Info.plist"
plutil -insert CFBundleIdentifier -string "com.shlyft.valhalla" "$contents_dir/Info.plist"
plutil -insert CFBundleExecutable -string "Valhalla" "$contents_dir/Info.plist"
plutil -insert CFBundlePackageType -string "APPL" "$contents_dir/Info.plist"
plutil -insert CFBundleIconFile -string "Valhalla" "$contents_dir/Info.plist"
plutil -insert CFBundleShortVersionString -string "0.2.0" "$contents_dir/Info.plist"
plutil -insert CFBundleVersion -string "2" "$contents_dir/Info.plist"
plutil -insert LSMinimumSystemVersion -string "13.0" "$contents_dir/Info.plist"
plutil -insert NSHighResolutionCapable -bool true "$contents_dir/Info.plist"
plutil -insert NSHumanReadableCopyright -string "Built for safe Samsung firmware workflows." "$contents_dir/Info.plist"

icon_work="$(mktemp -d)"
iconset_dir="$icon_work/Valhalla.iconset"
mkdir -p "$iconset_dir"
qlmanage -t -s 1024 -o "$icon_work" "$project_dir/Assets/ValhallaIcon.svg" >/dev/null 2>&1
icon_source="$icon_work/ValhallaIcon.svg.png"

sips -z 16 16 "$icon_source" --out "$iconset_dir/icon_16x16.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset_dir/icon_32x32.png" >/dev/null
sips -z 64 64 "$icon_source" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$icon_source" --out "$iconset_dir/icon_128x128.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset_dir/icon_256x256.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset_dir/icon_512x512.png" >/dev/null
cp "$icon_source" "$iconset_dir/icon_512x512@2x.png"
iconutil -c icns "$iconset_dir" -o "$resources_dir/Valhalla.icns"

codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
