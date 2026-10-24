#!/bin/zsh
# Builds Snapper.app and installs it to ~/Applications.
set -euo pipefail
cd "${0:A:h}"

APP=build/Snapper.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O main.swift -o "$APP/Contents/MacOS/Snapper" \
  -framework Cocoa -framework Carbon -framework ServiceManagement \
  -target "$(uname -m)-apple-macos13.0"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Snapper</string>
  <key>CFBundleDisplayName</key><string>Snapper</string>
  <key>CFBundleIdentifier</key><string>io.github.usman-kn.snapper</string>
  <key>CFBundleExecutable</key><string>Snapper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

mkdir -p ~/Applications
pkill -x Snapper 2>/dev/null || true
rm -rf ~/Applications/Snapper.app
cp -R "$APP" ~/Applications/
echo "Installed to ~/Applications/Snapper.app"
