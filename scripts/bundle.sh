#!/bin/bash
# Wraps a built Nimbus binary into a .app bundle and signs it on this Mac.
# Usage: scripts/bundle.sh <binary> <output .app> [version]
set -euo pipefail
cd "$(dirname "$0")/.."

BINARY="$1"
APP="$2"
VERSION="${3:-0.1.0}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Nimbus"
for f in Shortcuts/*.shortcut; do
    case "$f" in *unsigned*) ;; *) cp "$f" "$APP/Contents/Resources/" ;; esac
done 2>/dev/null || echo "Note: no signed shortcuts found, run scripts/make_shortcut.py"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.nimbus.app</string>
    <key>CFBundleName</key><string>Nimbus</string>
    <key>CFBundleExecutable</key><string>Nimbus</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Nimbus shows your next calendar event in the island.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Nimbus shows your next calendar event in the island.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Nimbus reads and controls Music and Spotify to show what is playing.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
