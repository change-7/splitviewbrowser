#!/usr/bin/env bash
set -euo pipefail

# Required environment variables:
#   DEVELOPER_ID_APP      e.g. Developer ID Application: Your Name (TEAMID)
#   DEVELOPER_ID_INSTALLER (optional for PKG flow; not used here)
#   APPLE_ID              Apple ID email
#   APPLE_APP_PASSWORD    App-specific password
#   TEAM_ID               Apple Developer Team ID
# Optional:
#   NOTARY_KEYCHAIN_PROFILE (preferred; if set, uses stored notarytool profile)

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${APP_PATH:-$PROJECT_DIR/SplitViewBrowser.app}"
DMG_PATH="${DMG_PATH:-$PROJECT_DIR/SplitViewBrowser-Installer.dmg}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

: "${DEVELOPER_ID_APP:?DEVELOPER_ID_APP is required}"

codesign --force --deep --options runtime --sign "$DEVELOPER_ID_APP" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

"$PROJECT_DIR/scripts/create_dmg.sh" "$APP_PATH" "$DMG_PATH"

if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
else
  : "${APPLE_ID:?APPLE_ID is required when NOTARY_KEYCHAIN_PROFILE is not set}"
  : "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required when NOTARY_KEYCHAIN_PROFILE is not set}"
  : "${TEAM_ID:?TEAM_ID is required when NOTARY_KEYCHAIN_PROFILE is not set}"
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait
fi

xcrun stapler staple "$DMG_PATH"
spctl -a -vv -t open "$DMG_PATH" || true

echo "Signed + notarized DMG ready: $DMG_PATH"
