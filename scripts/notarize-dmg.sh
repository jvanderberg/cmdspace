#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
profile="${1:-}"
dmg_path="${2:-}"

if [[ -z "$profile" ]]; then
    echo "Usage  $0 KEYCHAIN_PROFILE [DMG_PATH]" >&2
    exit 2
fi
if [[ -z "$dmg_path" ]]; then
    version="$(
        /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
            "$repo_dir/Resources/Info.plist"
    )"
    dmg_path="$repo_dir/dist/CmdSpace-$version.dmg"
fi

xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$profile" \
    --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
