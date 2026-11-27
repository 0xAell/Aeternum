#!/bin/sh
# Optional inputs are an existing pinned NorgannonDB checkout, a pinned Forever
# Dungeon Routes checkout and the compressed Classic world database.
set -eu
cd "$(dirname "$0")/.."
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

norg_commit=d3d144a8b2d32ae7fb6a0390141f35b3aa55d216
routes_commit=86fce2408d45e3240d7a798d5a0fc182a7c9e0f2
classic_commit=64adf9f62008df8d530e5d88e3c89aa85e42dc38
source=${1:-"$stage/norgannon"}
routes=${2:-"$stage/routes"}
classic=${3:-"$stage/classic.sql.gz"}
lua=${LUA:-luajit}

if [ ! -d "$source/.git" ]; then
    git clone --quiet --filter=blob:none --no-checkout https://github.com/zmarotrix/NorgannonDB.git "$source"
    git -C "$source" checkout --quiet "$norg_commit"
fi
test "$(git -C "$source" rev-parse HEAD)" = "$norg_commit"
if [ -n "${2:-}" ]; then
    test "$(git -C "$routes" rev-parse HEAD)" = "$routes_commit"
else
    folder="$routes/ForeverDungeonRoutes/Data"
    mkdir -p "$folder"
    for file in Dungeons Floors Rooms Pictures Minimaps DefaultRoutes; do
        curl -fsSL --retry 3 "https://raw.githubusercontent.com/Checkov23/ForeverDungeonRoutes/$routes_commit/ForeverDungeonRoutes/Data/$file.lua" -o "$folder/$file.lua"
    done
fi
if [ ! -f "$classic" ]; then
    curl -fsSL --retry 3 "https://raw.githubusercontent.com/cmangos/classic-db/$classic_commit/Full_DB/ClassicDB_1_12_1_z2815.sql.gz" -o "$classic"
fi

"$lua" tools/import_norgannon.lua "$source" "$stage/Data.lua"
"$lua" tools/import_floors.lua "$routes" "$stage/Data.lua" "$stage/FloorData.lua"
python3 tools/import_classic_training.py "$classic" "$stage/Data.lua" "$stage/ClassicTraining.lua"
for file in Data.lua FloorData.lua ClassicTraining.lua; do
    cmp "$file" "$stage/$file"
done
echo "All bundled data matches the pinned sources."
