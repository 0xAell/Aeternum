#!/bin/sh
# Builds dist/Aeternum-<version>.zip with an Aeternum folder ready for Interface/AddOns.
set -eu
cd "$(dirname "$0")/.."

version=$(sed -n 's/^## Version: //p' Aeternum.toc)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/Aeternum/licenses" dist
grep -v '^##' Aeternum.toc | grep . | while read -r file; do
    cp "$file" "$stage/Aeternum/"
done
cp Aeternum.toc LICENSE README.md DATA_SOURCES.md "$stage/Aeternum/"
cp licenses/* "$stage/Aeternum/licenses/"

archive="$PWD/dist/Aeternum-$version.zip"
rm -f "$archive"
(cd "$stage" && zip -qrX "$archive" Aeternum)
echo "$archive"
