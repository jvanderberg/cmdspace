#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$repo_dir/.build/CmdSpace.app"
contents_dir="$app_dir/Contents"

cd "$repo_dir"
swift build -c "$configuration"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$repo_dir/.build/$configuration/CmdSpace" "$contents_dir/MacOS/CmdSpace"
cp "$repo_dir/Resources/Info.plist" "$contents_dir/Info.plist"

icon_source="$repo_dir/Resources/AppIcon.png"
if [[ -f "$icon_source" ]]; then
    iconset_dir="$repo_dir/.build/AppIcon.iconset"
    rm -rf "$iconset_dir"
    mkdir -p "$iconset_dir"
    sips -z 16 16 "$icon_source" --out "$iconset_dir/icon_16x16.png" >/dev/null
    sips -z 32 32 "$icon_source" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$icon_source" --out "$iconset_dir/icon_32x32.png" >/dev/null
    sips -z 64 64 "$icon_source" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$icon_source" --out "$iconset_dir/icon_128x128.png" >/dev/null
    sips -z 256 256 "$icon_source" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$icon_source" --out "$iconset_dir/icon_256x256.png" >/dev/null
    sips -z 512 512 "$icon_source" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$icon_source" --out "$iconset_dir/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$icon_source" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$iconset_dir" -o "$contents_dir/Resources/AppIcon.icns"
fi

# Keep a stable signing identity when one is installed. TCC grants such as
# Full Disk Access are identity-keyed and then survive local rebuilds.
identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$identity" && "$configuration" == "release" ]]; then
    identity="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | awk -F'"' '/Developer ID Application/ {print $2; exit}'
    )"
fi
if [[ -n "$identity" && "$identity" != "-" ]]; then
    timestamp_args=()
    if [[ "${CODESIGN_TIMESTAMP:-0}" == "1" ]]; then
        timestamp_args+=(--timestamp)
    fi
    codesign --force --deep --options runtime "${timestamp_args[@]}" \
        --sign "$identity" "$app_dir"
else
    codesign --force --deep --sign - "$app_dir"
fi
echo "$app_dir"
