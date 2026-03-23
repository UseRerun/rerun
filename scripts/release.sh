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

# --- Version updates ---

echo "Updating version to $VERSION..."

sed -i '' 's/public static let version = "[^"]*"/public static let version = "'"$VERSION"'"/' \
  "${REPO_ROOT}/app/Sources/RerunCore/Rerun.swift"

sed -i '' 's/VERSION="${VERSION:-[^}]*}"/VERSION="${VERSION:-'"$VERSION"'}"/' \
  "${REPO_ROOT}/app/bundle.sh"

sed -i '' '/CFBundleShortVersionString/{n;s/<string>[^<]*</<string>'"$VERSION"'</;}' \
  "${REPO_ROOT}/app/dev.sh"

sed -i '' 's/#expect(Rerun.version == "[^"]*")/#expect(Rerun.version == "'"$VERSION"'")/' \
  "${REPO_ROOT}/app/Tests/RerunCoreTests/RerunCoreTests.swift"

echo "Updated version to $VERSION in all files"

# --- Build ---

echo "Building Rerun.app..."
cd "${REPO_ROOT}/app"
VERSION="$VERSION" CODESIGN_IDENTITY="$SIGNING_IDENTITY" ./bundle.sh prod

# --- DMG creation ---

APP_PATH="${REPO_ROOT}/app/build/Rerun.app"
DMG_PATH="${REPO_ROOT}/app/build/Rerun.dmg"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: build failed — $APP_PATH not found" >&2
  exit 1
fi

echo "Creating DMG..."
DMG_STAGING=$(mktemp -d)
cp -R "$APP_PATH" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

rm -f "$DMG_PATH"
hdiutil create -srcfolder "$DMG_STAGING" -volname "Rerun" -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGING"

echo ""
echo "Release built successfully:"
echo "  App: $APP_PATH"
echo "  DMG: $DMG_PATH"
echo "  Version: $VERSION"
