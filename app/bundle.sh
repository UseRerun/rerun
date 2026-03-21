#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

VARIANT="${1:-all}"
VERSION="${VERSION:-0.1.0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Sabotage Media, LLC (W33JZPPPFN)}"

case "$VARIANT" in
  all|prod|dev)
    ;;
  *)
    echo "Usage: ./bundle.sh [all|prod|dev]"
    exit 1
    ;;
esac

# Build release binaries
echo "Building release..."
swift build -c release

build_bundle() {
  local bundle_name="$1"
  local bundle_id="$2"
  local app_dir="build/${bundle_name}.app"
  local contents="${app_dir}/Contents"

  rm -rf "${app_dir}"
  mkdir -p "${contents}/MacOS"
  mkdir -p "${contents}/Resources"

  cp .build/release/rerun-daemon "${contents}/MacOS/${bundle_name}"

  cat > "${contents}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleName</key>
    <string>${bundle_name}</string>
    <key>CFBundleDisplayName</key>
    <string>${bundle_name}</string>
    <key>CFBundleExecutable</key>
    <string>${bundle_name}</string>
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

  codesign --force --sign "${CODESIGN_IDENTITY}" "${app_dir}"
  echo "Built: ${app_dir}"
}

mkdir -p build

if [[ "$VARIANT" == "all" || "$VARIANT" == "prod" ]]; then
  build_bundle "Rerun" "com.rerun.app"
fi

if [[ "$VARIANT" == "all" || "$VARIANT" == "dev" ]]; then
  build_bundle "RerunDev" "com.rerun.dev"
fi

echo ""
echo "To install:"
if [[ "$VARIANT" == "all" || "$VARIANT" == "prod" ]]; then
  echo "  cp -R build/Rerun.app /Applications/"
  echo "  open /Applications/Rerun.app"
fi
if [[ "$VARIANT" == "all" || "$VARIANT" == "dev" ]]; then
  echo "  cp -R build/RerunDev.app /Applications/"
  echo "  open /Applications/RerunDev.app"
fi
