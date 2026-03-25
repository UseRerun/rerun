#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

PROFILE="${RERUN_PROFILE:-dev}"
export RERUN_PROFILE="$PROFILE"

# On start: build debug RerunDev.app into /Applications so the dev app keeps a
# stable bundle path and TCC permissions across git worktrees.
if [[ ${1-} == "start" ]]; then
    swift build

    APP_DIR="/Applications/RerunDev.app"
    CONTENTS="${APP_DIR}/Contents"
    DEST="${CONTENTS}/MacOS/RerunDev"
    SRC=".build/debug/rerun-daemon"
    mkdir -p "${CONTENTS}/MacOS"

    # Only update the binary if the source actually changed — preserves TCC permissions.
    # We track the source hash separately because codesigning modifies the destination
    # binary, so direct cmp would always show a difference.
    HASH_FILE="/Applications/.rerundev-source-hash"
    SRC_HASH=$(md5 -q "$SRC")
    OLD_HASH=""
    if [[ -f "$HASH_FILE" ]]; then
        OLD_HASH=$(cat "$HASH_FILE")
    fi

    NEEDS_SIGN=0

    if [[ "$SRC_HASH" != "$OLD_HASH" ]]; then
        cp "$SRC" "$DEST"
        echo "$SRC_HASH" > "$HASH_FILE"
        NEEDS_SIGN=1

        # Ensure rpath for Sparkle framework
        install_name_tool -add_rpath @executable_path/../Frameworks "$DEST" 2>/dev/null || true

        # Compile MLX Metal shaders into metallib if needed
        MLX_METALLIB="${CONTENTS}/MacOS/mlx.metallib"
        CLI_METALLIB=".build/debug/mlx.metallib"
        MLX_METAL_DIR=".build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
        if [[ -d "$MLX_METAL_DIR" ]] && ! [[ -f "$MLX_METALLIB" ]]; then
            echo "Compiling MLX Metal shaders..."
            TMPDIR_AIR=$(mktemp -d)
            find "$MLX_METAL_DIR" -name "*.metal" | while read f; do
                AIR="${TMPDIR_AIR}/$(basename "${f%.metal}.air")"
                xcrun metal -c "$f" -I "$MLX_METAL_DIR" -o "$AIR" 2>/dev/null
            done
            find "$TMPDIR_AIR" -name "*.air" -print0 | xargs -0 xcrun metallib -o "$MLX_METALLIB" 2>/dev/null
            rm -rf "$TMPDIR_AIR"
            echo "MLX metallib compiled"
        fi
        # Also copy metallib to .build/debug/ so CLI binary can find it
        if [[ -f "$MLX_METALLIB" ]] && ! [[ -f "$CLI_METALLIB" ]]; then
            cp "$MLX_METALLIB" "$CLI_METALLIB"
        fi

        echo "Updated RerunDev.app binary"
    fi

    # Copy dev icon
    mkdir -p "${CONTENTS}/Resources"
    cp "resources/AppIconDev.icns" "${CONTENTS}/Resources/AppIconDev.icns" 2>/dev/null || true
    cp resources/MenuBarIcon.png "${CONTENTS}/Resources/MenuBarIcon.png" 2>/dev/null || true
    cp "resources/MenuBarIcon@2x.png" "${CONTENTS}/Resources/MenuBarIcon@2x.png" 2>/dev/null || true

    # Create Info.plist if missing
    if [[ ! -f "${CONTENTS}/Info.plist" ]]; then
        cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.rerun.dev</string>
    <key>CFBundleName</key>
    <string>RerunDev</string>
    <key>CFBundleDisplayName</key>
    <string>RerunDev</string>
    <key>CFBundleExecutable</key>
    <string>RerunDev</string>
    <key>CFBundleIconFile</key>
    <string>AppIconDev</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.1</string>
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
        NEEDS_SIGN=1
    fi

    # Determine signing identity — prefer Developer ID, fall back to ad-hoc
    CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Sabotage Media, LLC (W33JZPPPFN)}"
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "${CODESIGN_IDENTITY}"; then
        CODESIGN_IDENTITY="-"
    fi

    # Embed Sparkle framework if not already present
    SPARKLE_FW=$(find .build/artifacts -path "*/macos-arm64_x86_64/Sparkle.framework" -type d 2>/dev/null | head -1)
    if [[ -n "$SPARKLE_FW" ]] && [[ ! -d "${CONTENTS}/Frameworks/Sparkle.framework" ]]; then
        mkdir -p "${CONTENTS}/Frameworks"
        cp -a "$SPARKLE_FW" "${CONTENTS}/Frameworks/Sparkle.framework"
        install_name_tool -add_rpath @executable_path/../Frameworks "$DEST" 2>/dev/null || true

        # Sign framework internals (inner-to-outer, matching bundle.sh)
        FW="${CONTENTS}/Frameworks/Sparkle.framework"
        codesign --force --sign "${CODESIGN_IDENTITY}" "$FW/Versions/B/XPCServices/Downloader.xpc"
        codesign --force --sign "${CODESIGN_IDENTITY}" "$FW/Versions/B/XPCServices/Installer.xpc"
        codesign --force --sign "${CODESIGN_IDENTITY}" "$FW/Versions/B/Updater.app"
        codesign --force --sign "${CODESIGN_IDENTITY}" "$FW/Versions/B/Autoupdate"
        codesign --force --sign "${CODESIGN_IDENTITY}" "$FW/Versions/B/Sparkle"
        codesign --force --sign "${CODESIGN_IDENTITY}" "$FW"
        echo "Embedded Sparkle.framework"
        NEEDS_SIGN=1
    fi

    # Sign everything (after all bundle contents are assembled)
    if [[ $NEEDS_SIGN -eq 1 ]]; then
        if [[ -f "${CONTENTS}/MacOS/mlx.metallib" ]]; then
            codesign --force --sign "${CODESIGN_IDENTITY}" "${CONTENTS}/MacOS/mlx.metallib"
        fi
        codesign --force --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"
    fi
fi

args=("$@")
if [[ ${1-} == "start" ]]; then
    has_target=0
    for arg in "${args[@]}"; do
        if [[ "$arg" == "--target" || "$arg" == --target=* ]]; then
            has_target=1
            break
        fi
    done
    if [[ $has_target -eq 0 ]]; then
        args+=("--target" "installed")
    fi
fi

swift run rerun "${args[@]}"
