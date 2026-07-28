#!/usr/bin/env bash
# Assemble Claudemon.app from the SPM build.
#
# No Xcode required: the Command Line Tools ship the macOS SDK, and a menu bar
# agent only needs a binary plus an Info.plist in the right layout.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="Claudemon.app"
CONTENTS="$APP/Contents"

echo "Building ($CONFIG)..."
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Claudemon"
[ -x "$BIN" ] || { echo "no binary at $BIN" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/Claudemon"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Claudemon</string>
  <key>CFBundleDisplayName</key>       <string>Claudemon</string>
  <key>CFBundleExecutable</key>        <string>Claudemon</string>
  <key>CFBundleIdentifier</key>        <string>dev.sam.claudemon</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key>           <string>1</string>
  <key>LSMinimumSystemVersion</key>    <string>13.0</string>
  <!-- Menu bar agent: no Dock icon, no app switcher entry. -->
  <key>LSUIElement</key>               <true/>
  <!-- Shown when macOS asks to allow controlling Terminal for click-to-focus. -->
  <key>NSAppleEventsUsageDescription</key>
  <string>Claudemon focuses the Terminal tab running the session you clicked.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS keeps the Automation permission across rebuilds
# instead of re-prompting every time the binary changes.
codesign --force --sign - "$APP" >/dev/null 2>&1 || \
  echo "warning: ad-hoc codesign failed; Automation permission may re-prompt" >&2

echo "Built $(pwd)/$APP"
