#!/bin/sh
# Builds dist/Aeternum-<version>.zip with an Aeternum folder ready for Interface/AddOns.
set -eu
cd "$(dirname "$0")/.."

version=$(sed -n 's/^## Version: //p' Aeternum.toc)
mkdir -p dist
stage=$(mktemp -d "$PWD/dist/.aeternum-XXXXXXXX")
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/Aeternum/licenses"
grep -v '^##' Aeternum.toc | grep . | while read -r file; do
    cp "$file" "$stage/Aeternum/"
done
cp Aeternum.toc LICENSE README.md DATA_SOURCES.md "$stage/Aeternum/"
cp licenses/AllTheThings-MIT.txt \
    licenses/CMaNGOS-COPYRIGHT.md \
    licenses/ForeverBossData-NOTICE.md \
    licenses/ForeverDungeonRoutes-MIT.txt \
    licenses/NorgannonDB-NOTICE.md \
    licenses/WhatsTraining-MIT.txt \
    licenses/pfQuest-MIT.txt "$stage/Aeternum/licenses/"

archive="$PWD/dist/Aeternum-$version.zip"
(cd "$stage" && zip -qrX release.zip Aeternum)
mv -f "$stage/release.zip" "$archive"
echo "$archive"
