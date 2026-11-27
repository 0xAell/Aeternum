#!/bin/sh
# Regenerates Data.lua from the pinned NorgannonDB commit and fails if it differs.
# Usage: tools/check_data.sh [SOURCE_DIR]   (cloned there when missing)
set -eu
cd "$(dirname "$0")/.."

commit=d3d144a8b2d32ae7fb6a0390141f35b3aa55d216
source=${1:-../aeternum-source-norgannondb}
lua=${LUA:-luajit}

if [ ! -d "$source/.git" ]; then
    git clone --quiet --filter=blob:none https://github.com/zmarotrix/NorgannonDB.git "$source"
fi
git -C "$source" checkout --quiet "$commit"

generated=$(mktemp)
trap 'rm -f "$generated"' EXIT
"$lua" tools/import_norgannon.lua "$source" "$generated"
if cmp -s Data.lua "$generated"; then
    echo "Data.lua matches NorgannonDB $commit"
else
    echo "Data.lua differs from a fresh import; run tools/import_norgannon.lua" >&2
    exit 1
fi
