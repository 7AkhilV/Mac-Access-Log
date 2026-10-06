#!/bin/zsh
set -euo pipefail

# Builds AccessLog.app (Release) and a drag-and-drop DMG installer.
#
# Usage:
#   ./scripts/build-installer.sh
#
# Optional — pre-seed Google config into the app (users skip credential/sheet steps):
#   ./scripts/build-installer.sh \
#     --credentials "/path/to/service-account.json" \
#     --spreadsheet-id "1f23QbaB…" \
#     --sheet-name "Access Logs"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP_NAME="AccessLog"
DMG_NAME="AccessLog-Installer"
CREDENTIALS=""
SPREADSHEET_ID=""
SHEET_NAME="Access Logs"
LOCAL_SUPPORT="${HOME}/Library/Application Support/AccessLog"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --credentials) CREDENTIALS="$2"; shift 2 ;;
    --spreadsheet-id) SPREADSHEET_ID="$2"; shift 2 ;;
    --sheet-name) SHEET_NAME="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Default: bundle this Mac's service account only. Each install keeps its own Sheet.
if [[ -z "$CREDENTIALS" && -f "$LOCAL_SUPPORT/credentials.json" ]]; then
  CREDENTIALS="$LOCAL_SUPPORT/credentials.json"
fi

echo "→ Building Release…"
OAUTH_JSON="$ROOT/AccessLog/Resources/GoogleOAuth.json"
if [[ ! -f "$OAUTH_JSON" ]] || grep -q "YOUR_CLIENT_ID" "$OAUTH_JSON"; then
  echo "Missing real OAuth config."
  echo "Copy AccessLog/Resources/GoogleOAuth.example.json → GoogleOAuth.json and fill client_id/secret."
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$ROOT/AccessLog.xcodeproj" \
  -scheme AccessLog \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  build

APP_SRC="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "Build failed: $APP_SRC not found"
  exit 1
fi

STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_SRC" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

# Optional seed so Macs get credentials/config automatically on first launch
if [[ -n "$CREDENTIALS" || -n "$SPREADSHEET_ID" ]]; then
  SEED="$STAGE/$APP_NAME.app/Contents/Resources/Seed"
  mkdir -p "$SEED"
  if [[ -n "$CREDENTIALS" ]]; then
    cp "$CREDENTIALS" "$SEED/credentials.json"
    echo "→ Bundled credentials.json"
  fi
  if [[ -n "$SPREADSHEET_ID" ]]; then
    cat > "$SEED/config.json" <<EOF
{
  "spreadsheetId": "$SPREADSHEET_ID",
  "sheetName": "$SHEET_NAME"
}
EOF
    echo "→ Bundled config.json"
  fi
fi

SA_EMAIL=""
if [[ -n "$CREDENTIALS" && -f "$CREDENTIALS" ]]; then
  SA_EMAIL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("client_email",""))' "$CREDENTIALS")"
fi

cat > "$STAGE/INSTALL.txt" <<EOF
Access Log — Install
====================

1. Drag AccessLog into Applications and open it.
2. In Google Drive, create a Sheet (or use the one this Mac already uses).
   First row: ID | Name | Purpose | Date | Time
3. Share THAT Sheet as Editor with:
   ${SA_EMAIL:-the service-account email shown in the app}
4. In the Access Log wizard, paste your Sheet link and run the connection test.

Do not sign in with Google.
New users: use your own Sheet.
Existing users: keep this Mac’s current Sheet; only add the email above as Editor.

Keep the app running so it can open after Mac unlock.
Re-open setup: Access Log menu → Run Setup Wizard…
EOF

DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Access Log" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo ""
echo "✓ Installer ready:"
echo "  $DMG_PATH"
echo ""
echo "Give users that DMG. They only need to share the Sheet with the service-account email as Editor."
