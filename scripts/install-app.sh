#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-release}"
source_app="$repo_dir/.build/CmdSpace.app"
installed_app="/Applications/CmdSpace.app"

"$repo_dir/scripts/build-app.sh" "$configuration"

# ditto preserves the signed bundle exactly. Updating in place keeps both the
# bundle path and Developer ID designated requirement stable for macOS TCC.
ditto "$source_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"

running_pid="$(pgrep -n -x CmdSpace || true)"
if [[ -n "$running_pid" ]]; then
    kill "$running_pid"
    for _ in {1..50}; do
        if ! kill -0 "$running_pid" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done
fi
open -n "$installed_app"
sleep 1

launched_pid="$(pgrep -n -f '/Applications/CmdSpace.app/Contents/MacOS/CmdSpace' || true)"
if [[ -z "$launched_pid" ]]; then
    echo "CmdSpace did not remain running after launch" >&2
    exit 1
fi

echo "Installed and launched $installed_app"
