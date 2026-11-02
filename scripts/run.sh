#!/bin/bash
# Build Nimbus, wrap it in a .app bundle (needed for the Automation permission
# prompt and LSUIElement), ad-hoc sign it and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

APP="build/Nimbus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/Nimbus" "$APP/Contents/MacOS/Nimbus"
mkdir -p "$APP/Contents/Resources"
for f in Shortcuts/*.shortcut; do case "$f" in *unsigned*) ;; *) cp "$f" "$APP/Contents/Resources/" ;; esac; done 2>/dev/null || echo "Note: no signed shortcuts found, run scripts/make_shortcut.py"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.nimbus.app</string>
    <key>CFBundleName</key><string>Nimbus</string>
    <key>CFBundleExecutable</key><string>Nimbus</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
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
pkill -x Nimbus 2>/dev/null || true
open "$APP"
echo "Launched $APP"
