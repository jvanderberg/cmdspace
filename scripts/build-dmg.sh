#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
version="$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$repo_dir/Resources/Info.plist"
)"
output_dir="$repo_dir/dist"
output_dmg="$output_dir/CmdSpace-$version.dmg"
work_dir="$(mktemp -d)"
staging_dir="$work_dir/stage"
mount_dir="$work_dir/mount"
mounted=0

cleanup() {
    if [[ "$mounted" == "1" ]]; then
        hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT

if [[ "${SKIP_APP_BUILD:-0}" != "1" ]]; then
    "$repo_dir/scripts/build-app.sh" release
fi
mkdir -p "$output_dir"
mkdir -p "$staging_dir" "$mount_dir"
ditto "$repo_dir/.build/CmdSpace.app" "$staging_dir/CmdSpace.app"
ln -s /Applications "$staging_dir/Applications"

rm -f "$output_dmg"
hdiutil create \
    -volname "CmdSpace" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDRW \
    "$work_dir/CmdSpace-rw.dmg"
hdiutil attach "$work_dir/CmdSpace-rw.dmg" \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$mount_dir" >/dev/null
mounted=1
cp "$repo_dir/.build/CmdSpace.app/Contents/Resources/AppIcon.icns" \
    "$mount_dir/.VolumeIcon.icns"
xcrun SetFile -a C "$mount_dir"
hdiutil detach "$mount_dir" >/dev/null
mounted=0
hdiutil convert "$work_dir/CmdSpace-rw.dmg" \
    -format UDZO \
    -o "$output_dmg" >/dev/null

identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
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
    codesign --force "${timestamp_args[@]}" --sign "$identity" "$output_dmg"
    codesign --verify --verbose=2 "$output_dmg"
fi

shasum -a 256 "$output_dmg" > "$output_dmg.sha256"
echo "$output_dmg"
