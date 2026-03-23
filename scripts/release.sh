#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Argument validation ---

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: scripts/release.sh <version>" >&2
  echo "Example: scripts/release.sh 0.2.0" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be semver (e.g. 0.2.0), got: $VERSION" >&2
  exit 1
fi

# --- Environment loading ---

ENV_FILE="${REPO_ROOT}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: .env not found at $ENV_FILE" >&2
  echo "Copy .env.example to .env and fill in your values." >&2
  exit 1
fi

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

strip_matching_quotes() {
  local value="$1"
  if [[ ${#value} -ge 2 ]]; then
    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s' "$value"
}

APPLE_TEAM_ID=""
APPLE_ID=""
SIGNING_IDENTITY_NAME=""

while IFS='=' read -r raw_key raw_value; do
  [[ -z "${raw_key//[[:space:]]/}" ]] && continue
  [[ "$raw_key" =~ ^[[:space:]]*# ]] && continue

  key="$(trim_whitespace "$raw_key")"
  value="$(trim_whitespace "$raw_value")"
  value="$(strip_matching_quotes "$value")"

  case "$key" in
    APPLE_TEAM_ID)
      APPLE_TEAM_ID="$value"
      ;;
    APPLE_ID)
      APPLE_ID="$value"
      ;;
    SIGNING_IDENTITY_NAME)
      SIGNING_IDENTITY_NAME="$value"
      ;;
  esac
done < "$ENV_FILE"

for var in APPLE_TEAM_ID APPLE_ID SIGNING_IDENTITY_NAME; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: $var is not set in .env" >&2
    exit 1
  fi
done

SIGNING_IDENTITY="Developer ID Application: ${SIGNING_IDENTITY_NAME} (${APPLE_TEAM_ID})"

create_dmg() {
  local app_path="$1"
  local dmg_path="$2"
  local dmg_staging

  dmg_staging=$(mktemp -d)
  cp -R "$app_path" "${dmg_staging}/"
  ln -s /Applications "${dmg_staging}/Applications"

  rm -f "$dmg_path"
  hdiutil create -srcfolder "$dmg_staging" -volname "Rerun" -format UDZO "$dmg_path"
  rm -rf "$dmg_staging"
}

extract_changelog() {
  local version="$1"
  local changelog="$2"
  local in_section=false
  local html="<ul>"

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[${version}\] ]]; then
      in_section=true
      continue
    fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then
      break
    fi
    if $in_section && [[ "$line" =~ ^-\ (.+) ]]; then
      html+="<li>${BASH_REMATCH[1]}</li>"
    fi
  done < "$changelog"

  html+="</ul>"
  if [ "$html" = "<ul></ul>" ]; then
    echo ""
  else
    echo "$html"
  fi
}

extract_changelog_markdown() {
  local version="$1"
  local changelog="$2"
  local in_section=false
  local md=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[${version}\] ]]; then
      in_section=true
      continue
    fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then
      break
    fi
    if $in_section && [[ "$line" =~ ^-\ (.+) ]]; then
      md+="- ${BASH_REMATCH[1]}"$'\n'
    fi
  done < "$changelog"

  echo "$md"
}

extract_swift_version() {
  sed -n 's/.*public static let version = "\([^"]*\)".*/\1/p' "$1" | head -n 1
}

extract_bundle_default_version() {
  sed -n 's/^VERSION="\${VERSION:-\([^"]*\)}"/\1/p' "$1" | head -n 1
}

extract_plist_version() {
  awk '
    /CFBundleShortVersionString/ {
      getline
      if (match($0, /<string>([^<]+)<\/string>/)) {
        value = substr($0, RSTART + 8, RLENGTH - 17)
        print value
        exit
      }
    }
  ' "$1"
}

extract_test_version() {
  sed -n 's/.*#expect(Rerun.version == "\([^"]*\)").*/\1/p' "$1" | head -n 1
}

require_version_match() {
  local file="$1"
  local actual="$2"

  if [[ "$actual" != "$VERSION" ]]; then
    echo "Error: ${file} has version ${actual:-<missing>}, expected $VERSION." >&2
    echo "Update version files and commit them before running scripts/release.sh." >&2
    exit 1
  fi
}

# --- Pre-flight checks ---

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
  echo "Error: working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

require_version_match "app/Sources/RerunCore/Rerun.swift" \
  "$(extract_swift_version "${REPO_ROOT}/app/Sources/RerunCore/Rerun.swift")"
require_version_match "app/bundle.sh" \
  "$(extract_bundle_default_version "${REPO_ROOT}/app/bundle.sh")"
require_version_match "app/dev.sh" \
  "$(extract_plist_version "${REPO_ROOT}/app/dev.sh")"
require_version_match "app/Tests/RerunCoreTests/RerunCoreTests.swift" \
  "$(extract_test_version "${REPO_ROOT}/app/Tests/RerunCoreTests/RerunCoreTests.swift")"

if ! xcrun notarytool history --keychain-profile "AC_PASSWORD" >/dev/null 2>&1; then
  echo "Error: notarytool keychain profile \"AC_PASSWORD\" not found or invalid." >&2
  echo "Set it up with:" >&2
  echo "  xcrun notarytool store-credentials \"AC_PASSWORD\" --apple-id \"\$APPLE_ID\" --team-id \"\$APPLE_TEAM_ID\" --password \"<app-specific-password>\"" >&2
  exit 1
fi

# --- Build ---

echo "Building Rerun.app..."
cd "${REPO_ROOT}/app"
VERSION="$VERSION" CODESIGN_IDENTITY="$SIGNING_IDENTITY" ./bundle.sh prod

# --- DMG creation ---

APP_PATH="${REPO_ROOT}/app/build/Rerun.app"
APP_ZIP_PATH="${REPO_ROOT}/app/build/Rerun-notarization.zip"
DMG_PATH="${REPO_ROOT}/app/build/Rerun.dmg"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: build failed — $APP_PATH not found" >&2
  exit 1
fi

echo "Creating app archive for notarization..."
rm -f "$APP_ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP_PATH"

echo "Notarizing app archive..."
xcrun notarytool submit "$APP_ZIP_PATH" --keychain-profile "AC_PASSWORD" --wait

echo "Stapling app..."
xcrun stapler staple "$APP_PATH"

echo "Creating DMG..."
create_dmg "$APP_PATH" "$DMG_PATH"

echo "Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

echo "Notarizing DMG..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "AC_PASSWORD" --wait

echo "Stapling DMG..."
xcrun stapler staple "$DMG_PATH" || echo "Warning: DMG staple failed (normal — CDN propagation delay). App inside is stapled."
rm -f "$APP_ZIP_PATH"

# --- Tag + GitHub Release ---

echo "Tagging v$VERSION..."
git -C "$REPO_ROOT" tag "v$VERSION"
git -C "$REPO_ROOT" push origin "v$VERSION"

echo "Creating GitHub release..."
CHANGELOG_MD=$(extract_changelog_markdown "$VERSION" "${REPO_ROOT}/CHANGELOG.md")
if [ -n "$CHANGELOG_MD" ]; then
  gh release create "v$VERSION" "$DMG_PATH" \
    --title "Rerun v$VERSION" \
    --notes "$CHANGELOG_MD"
else
  gh release create "v$VERSION" "$DMG_PATH" \
    --title "Rerun v$VERSION" \
    --generate-notes
fi

# --- Appcast generation ---

echo "Generating appcast..."
SPARKLE_BIN=$(find "${REPO_ROOT}/app/.build/artifacts" -path "*/sparkle/Sparkle/bin" -maxdepth 4 -type d 2>/dev/null | head -1)
if [[ -z "$SPARKLE_BIN" ]]; then
  echo "Error: Sparkle bin not found in .build/artifacts" >&2
  exit 1
fi

SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG_PATH" 2>&1)
ED_SIG=$(echo "$SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGNATURE" | grep -o 'length="[^"]*"' | cut -d'"' -f2)
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

CHANGELOG_HTML=$(extract_changelog "$VERSION" "${REPO_ROOT}/CHANGELOG.md")

APPCAST_PATH="${REPO_ROOT}/website/public/appcast.xml"
EXISTING_ITEMS=""
if [ -f "$APPCAST_PATH" ]; then
  EXISTING_ITEMS=$(awk '
    /<item>/ { buf=""; capture=1 }
    capture { buf = buf $0 "\n" }
    /<\/item>/ {
      capture=0
      if (buf !~ /<sparkle:version>'"$VERSION"'</) printf "%s", buf
    }
  ' "$APPCAST_PATH")
fi

DESCRIPTION=""
if [ -n "$CHANGELOG_HTML" ]; then
  DESCRIPTION="      <description><![CDATA[$CHANGELOG_HTML]]></description>"
fi

cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
  <channel>
    <title>Rerun</title>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <pubDate>$PUB_DATE</pubDate>
$DESCRIPTION
      <enclosure
        url="https://github.com/usererun/rerun/releases/download/v$VERSION/Rerun.dmg"
        sparkle:edSignature="$ED_SIG"
        length="$LENGTH"
        type="application/octet-stream"
      />
    </item>
$EXISTING_ITEMS
  </channel>
</rss>
EOF

echo "Updating appcast..."
git -C "$REPO_ROOT" add website/public/appcast.xml
git -C "$REPO_ROOT" commit -m "chore: update appcast for v$VERSION"
git -C "$REPO_ROOT" push

# --- Update website version ---

echo "Updating website version.json..."
mkdir -p "${REPO_ROOT}/website/src/data"
cat > "${REPO_ROOT}/website/src/data/version.json" <<VJSON
{ "version": "$VERSION" }
VJSON
git -C "$REPO_ROOT" add website/src/data/version.json
if git -C "$REPO_ROOT" diff --cached --quiet -- website/src/data/version.json; then
  echo "Website version already at v$VERSION; skipping commit."
else
  git -C "$REPO_ROOT" commit -m "chore: update website version to v$VERSION"
  git -C "$REPO_ROOT" push
fi

echo ""
echo "Release complete:"
echo "  Version: $VERSION"
echo "  DMG: $DMG_PATH"
echo "  Appcast: website/public/appcast.xml"
echo "  Version JSON: website/src/data/version.json"
echo "  GitHub: https://github.com/usererun/rerun/releases/tag/v$VERSION"
