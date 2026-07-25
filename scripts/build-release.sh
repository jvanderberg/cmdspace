#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
profile="${1:-cmdspace-notary}"
version="$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$repo_dir/Resources/Info.plist"
)"
app_path="$repo_dir/.build/CmdSpace.app"
dmg_path="$repo_dir/dist/CmdSpace-$version.dmg"
work_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

if [[ -n "${NOTARY_APPLE_ID:-}" ]]; then
    notary_auth=(
        --apple-id "$NOTARY_APPLE_ID"
        --password "$NOTARY_PASSWORD"
        --team-id "$NOTARY_TEAM_ID"
    )
else
    notary_auth=(--keychain-profile "$profile")
fi

CODESIGN_TIMESTAMP=1 "$repo_dir/scripts/build-app.sh" release
codesign --verify --deep --strict --verbose=2 "$app_path"

ditto -c -k --keepParent "$app_path" "$work_dir/CmdSpace.zip"
xcrun notarytool submit "$work_dir/CmdSpace.zip" \
    "${notary_auth[@]}" \
    --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"

SKIP_APP_BUILD=1 CODESIGN_TIMESTAMP=1 "$repo_dir/scripts/build-dmg.sh"
xcrun notarytool submit "$dmg_path" \
    "${notary_auth[@]}" \
    --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature \
    --verbose=2 "$dmg_path"
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"

echo "$dmg_path"
