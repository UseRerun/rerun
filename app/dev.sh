#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

PROFILE="${RERUN_PROFILE:-dev}"
export RERUN_PROFILE="$PROFILE"

# On start: build debug RerunDev.app so --target local finds a real app bundle.
# This gives the dev daemon a proper bundle ID (com.rerun.dev) for TCC permissions,
# NSApplication, status bar, hotkeys, and all other app-bundle-only behavior.
if [[ ${1-} == "start" ]]; then
    swift build

    APP_DIR="build/RerunDev.app"
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
        CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Sabotage Media, LLC (W33JZPPPFN)}"
        codesign --force --sign "${CODESIGN_IDENTITY}" "${APP_DIR}" 2>/dev/null || codesign --force --sign - "${APP_DIR}" 2>/dev/null || true
        echo "Updated RerunDev.app binary"
    fi

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
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
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
        args+=("--target" "local")
    fi
fi

swift run rerun "${args[@]}"
