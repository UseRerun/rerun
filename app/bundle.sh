#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

BUNDLE_NAME="Rerun"
BUNDLE_ID="com.rerun.app"
VERSION="0.1.0"
APP_DIR="build/${BUNDLE_NAME}.app"
CONTENTS="${APP_DIR}/Contents"

# Build release binaries
echo "Building release..."
swift build -c release

# Clean previous bundle
rm -rf "${APP_DIR}"

# Create bundle structure
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"

# Copy daemon binary (renamed to match CFBundleExecutable)
cp .build/release/rerun-daemon "${CONTENTS}/MacOS/${BUNDLE_NAME}"

# Create Info.plist
cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${BUNDLE_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${BUNDLE_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${BUNDLE_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
</dict>
</plist>
PLIST

# Code sign with Developer ID (stable identity for TCC permissions)
codesign --force --sign "Developer ID Application: Sabotage Media, LLC (W33JZPPPFN)" "${APP_DIR}"

echo ""
echo "Built: ${APP_DIR}"
echo ""
echo "To install:"
echo "  cp -R ${APP_DIR} /Applications/"
echo "  open /Applications/${BUNDLE_NAME}.app"
