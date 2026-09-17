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
MOUNT_POINT="$TMP/mnt"
MOUNTED=0

cleanup() {
  if [[ "$MOUNTED" -eq 1 ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "→ Installing Access Log…"

DMG_PATH="${1:-}"

if [[ -z "$DMG_PATH" ]]; then
  echo "→ Downloading latest release DMG from GitHub…"
  if command -v gh >/dev/null 2>&1; then
    gh release download --repo "$REPO" --pattern "*.dmg" --dir "$TMP"
    DMG_PATH="$(print -l "$TMP"/*.dmg(N) | head -1)"
  else
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
  fi
fi

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: ${DMG_PATH:-"(empty)"}"
  exit 1
fi

echo "→ Using DMG: $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))"
echo "→ Mounting DMG…"
mkdir -p "$MOUNT_POINT"
# Fixed mountpoint avoids /Volumes names with spaces breaking path parsing.
if ! hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_POINT"; then
  echo "hdiutil attach failed for: $DMG_PATH"
  file "$DMG_PATH" || true
  exit 1
fi
MOUNTED=1
echo "→ Mounted at: $MOUNT_POINT"

APP_SRC="$(find "$MOUNT_POINT" -maxdepth 3 -name "${APP_NAME}.app" -type d | head -1)"
if [[ -z "$APP_SRC" ]]; then
  echo "AccessLog.app not found inside the DMG. Contents:"
  ls -la "$MOUNT_POINT"
  exit 1
fi

echo "→ Copying to ${INSTALL_DIR}…"
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "$APP_SRC" "${INSTALL_DIR}/"

echo "→ Detaching DMG…"
hdiutil detach "$MOUNT_POINT" -quiet || true
MOUNTED=0

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
