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
    HASH_FILE="${CONTENTS}/.source-hash"
    SRC_HASH=$(md5 -q "$SRC")
    OLD_HASH=""
    if [[ -f "$HASH_FILE" ]]; then
        OLD_HASH=$(cat "$HASH_FILE")
    fi

    if [[ "$SRC_HASH" != "$OLD_HASH" ]]; then
        cp "$SRC" "$DEST"
        echo "$SRC_HASH" > "$HASH_FILE"

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

        CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Sabotage Media, LLC (W33JZPPPFN)}"
        codesign --force --sign "${CODESIGN_IDENTITY}" "${APP_DIR}" 2>/dev/null || codesign --force --sign - "${APP_DIR}" 2>/dev/null || true
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
    <string>0.1.1</string>
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
