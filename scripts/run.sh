#!/bin/bash
# Build Nimbus, bundle it as build/Nimbus.app, sign it on this Mac and launch it.
# Usage: scripts/run.sh [debug|release]   (release is faster and lighter on the CPU)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"
scripts/bundle.sh ".build/$CONFIG/Nimbus" build/Nimbus.app

pkill -x Nimbus 2>/dev/null || true
open build/Nimbus.app
echo "Launched build/Nimbus.app"
