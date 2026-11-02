#!/bin/bash
# Builds the zip people download: Nimbus.app plus a short "how to open" note.
# Usage: scripts/package.sh [version]      -> dist/Nimbus-AppleSilicon.zip
# The file name never changes, so ".../releases/latest/download/Nimbus-AppleSilicon.zip" always works.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
STAGE="dist/stage"
ZIP="dist/Nimbus-AppleSilicon.zip"

swift build -c release
rm -rf dist
mkdir -p "$STAGE"
scripts/bundle.sh .build/release/Nimbus "$STAGE/Nimbus.app" "$VERSION"
cp docs/How-to-open-Nimbus.txt "$STAGE/How to open Nimbus.txt"

# ditto keeps the signature and file attributes intact; plain zip can break them.
ditto -c -k --sequesterRsrc "$STAGE" "$ZIP"
echo "Built $ZIP ($(du -h "$ZIP" | cut -f1))"
