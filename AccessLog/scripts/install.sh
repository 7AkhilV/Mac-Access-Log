#!/bin/zsh
set -euo pipefail

# Access Log — terminal installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/7AkhilV/Mac-Access-Log/main/AccessLog/scripts/install.sh | zsh
# Or locally:
#   ./scripts/install.sh
#   ./scripts/install.sh /path/to/AccessLog-Installer.dmg

APP_NAME="AccessLog"
REPO="7AkhilV/Mac-Access-Log"
INSTALL_DIR="/Applications"
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "→ Installing Access Log…"

DMG_PATH="${1:-}"

if [[ -z "$DMG_PATH" ]]; then
  echo "→ Downloading latest release DMG from GitHub…"
  if ! command -v gh >/dev/null 2>&1; then
    # Fallback: GitHub API + curl
    API="https://api.github.com/repos/${REPO}/releases/latest"
    DMG_URL="$(curl -fsSL "$API" | python3 -c '
import json,sys
rel=json.load(sys.stdin)
for a in rel.get("assets",[]):
    if a["name"].endswith(".dmg"):
        print(a["browser_download_url"]); break
')"
    if [[ -z "$DMG_URL" ]]; then
      echo "Could not find a .dmg on the latest GitHub release."
      echo "Pass a local DMG path: ./install.sh ~/Downloads/AccessLog-Installer.dmg"
      exit 1
    fi
    DMG_PATH="$TMP/AccessLog-Installer.dmg"
    curl -fL "$DMG_URL" -o "$DMG_PATH"
  else
    gh release download --repo "$REPO" --pattern "*.dmg" --dir "$TMP"
    DMG_PATH="$(ls "$TMP"/*.dmg | head -1)"
  fi
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH"
  exit 1
fi

echo "→ Mounting DMG…"
MOUNT_OUT="$(hdiutil attach "$DMG_PATH" -nobrowse)"
MOUNT_POINT="$(echo "$MOUNT_OUT" | awk '/\/Volumes\//{print $NF; exit}')"
if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "Failed to mount DMG."
  exit 1
fi

APP_SRC="$(find "$MOUNT_POINT" -maxdepth 2 -name "${APP_NAME}.app" -type d | head -1)"
if [[ -z "$APP_SRC" ]]; then
  echo "AccessLog.app not found inside the DMG."
  hdiutil detach "$MOUNT_POINT" -quiet || true
  exit 1
fi

echo "→ Copying to ${INSTALL_DIR}…"
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "$APP_SRC" "${INSTALL_DIR}/"

echo "→ Detaching DMG…"
hdiutil detach "$MOUNT_POINT" -quiet || true

# Clear Gatekeeper quarantine so unsigned local builds open without the malware dialog.
# Only run this for software you trust (this installer from your org / this GitHub repo).
echo "→ Clearing quarantine attribute…"
xattr -cr "${INSTALL_DIR}/${APP_NAME}.app"

echo "→ Opening Access Log…"
open "${INSTALL_DIR}/${APP_NAME}.app"

echo ""
echo "✓ Installed to ${INSTALL_DIR}/${APP_NAME}.app"
echo "  Complete the setup wizard (Sign in with Google → Sheet → test)."
echo "  Keep the app running so it can open after Mac unlock."
