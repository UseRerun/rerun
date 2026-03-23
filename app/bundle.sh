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

ensure_mlx_metallib() {
  local cli_metallib=".build/release/mlx.metallib"
  local mlx_metal_dir=".build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"

  if [[ -f "$cli_metallib" ]]; then
    return
  fi

  if [[ ! -d "$mlx_metal_dir" ]]; then
    echo "Missing MLX Metal sources: $mlx_metal_dir" >&2
    exit 1
  fi

  echo "Compiling MLX Metal shaders..."
  local tmpdir_air
  tmpdir_air=$(mktemp -d)

  while IFS= read -r -d '' f; do
    local air="${tmpdir_air}/$(basename "${f%.metal}.air")"
    xcrun metal -c "$f" -I "$mlx_metal_dir" -o "$air"
  done < <(find "$mlx_metal_dir" -name "*.metal" -print0)

  find "$tmpdir_air" -name "*.air" -print0 | xargs -0 xcrun metallib -o "$cli_metallib"
  rm -rf "$tmpdir_air"

  if [[ ! -f "$cli_metallib" ]]; then
    echo "Failed to build MLX metallib" >&2
    exit 1
  fi
}

build_bundle() {
  local bundle_name="$1"
  local bundle_id="$2"
  local app_dir="build/${bundle_name}.app"
  local contents="${app_dir}/Contents"
  local app_metallib="${contents}/MacOS/mlx.metallib"
  local entitlements_file=""

  rm -rf "${app_dir}"
  mkdir -p "${contents}/MacOS"
  mkdir -p "${contents}/Resources"

  cp .build/release/rerun-daemon "${contents}/MacOS/${bundle_name}"
  cp .build/release/mlx.metallib "$app_metallib"

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
    <string>${VERSION}</string>
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

  # RerunDaemon links Sparkle dynamically once the package product is added,
  # so every app bundle needs the framework to launch. Only prod gets update metadata.
  if [[ "$bundle_id" == "com.rerun.app" || "$bundle_id" == "com.rerun.dev" ]]; then
    local sparkle_fw
    sparkle_fw=$(find .build/artifacts -path "*/macos-arm64_x86_64/Sparkle.framework" -type d | head -1)
    if [[ -z "$sparkle_fw" ]]; then
      echo "Sparkle.framework not found in .build/artifacts" >&2
      exit 1
    fi

    if [[ "$bundle_id" == "com.rerun.app" ]]; then
      # Sparkle metadata stays prod-only until updater wiring lands.
      /usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://usererun.com/appcast.xml" "${contents}/Info.plist"
      /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string I1gi82QlV84mZZXMzxJyVMFKpDCmcatBYVSGcq1nJgE=" "${contents}/Info.plist"
    fi

    # Copy framework
    mkdir -p "${contents}/Frameworks"
    cp -a "$sparkle_fw" "${contents}/Frameworks/Sparkle.framework"

    # Add rpath so binary finds framework at Contents/Frameworks/
    install_name_tool -add_rpath @executable_path/../Frameworks "${contents}/MacOS/${bundle_name}"

    # Sign framework internals (inner components first)
    local fw="${contents}/Frameworks/Sparkle.framework"
    codesign --force --options runtime --sign "${CODESIGN_IDENTITY}" "$fw/Versions/B/XPCServices/Downloader.xpc"
    codesign --force --options runtime --sign "${CODESIGN_IDENTITY}" "$fw/Versions/B/XPCServices/Installer.xpc"
    codesign --force --options runtime --sign "${CODESIGN_IDENTITY}" "$fw/Versions/B/Updater.app"
    codesign --force --options runtime --sign "${CODESIGN_IDENTITY}" "$fw/Versions/B/Autoupdate"
    codesign --force --options runtime --sign "${CODESIGN_IDENTITY}" "$fw/Versions/B/Sparkle"
    codesign --force --options runtime --sign "${CODESIGN_IDENTITY}" "$fw"
  fi

  codesign --force --sign "${CODESIGN_IDENTITY}" "$app_metallib"

  local -a app_codesign_args=(--force --options runtime --sign "${CODESIGN_IDENTITY}")
  if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
    entitlements_file=$(mktemp)
    cat > "${entitlements_file}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
PLIST
    app_codesign_args+=(--entitlements "${entitlements_file}")
  fi

  codesign "${app_codesign_args[@]}" "${app_dir}"
  [[ -n "${entitlements_file}" ]] && rm -f "${entitlements_file}"
  echo "Built: ${app_dir}"
}

mkdir -p build
ensure_mlx_metallib

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
