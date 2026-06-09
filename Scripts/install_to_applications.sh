#!/usr/bin/env bash
set -euo pipefail

# Installs the packaged toolbox into /Applications so it runs from a realistic
# location — needed to test Sparkle auto-update, which won't update an app from
# a read-only or external path. Build first with Scripts/package_app.sh.
#
# Override the destination with INSTALL_DIR=/some/dir if desired.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DMonte Tool Box.app"
LEGACY_APP_NAME="DMonte Toolbox.app"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
DEST_DIR="${INSTALL_DIR:-/Applications}"
DEST_APP="$DEST_DIR/$APP_NAME"
LEGACY_DEST_APP="$DEST_DIR/$LEGACY_APP_NAME"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "error: $SOURCE_APP not found — run Scripts/package_app.sh first." >&2
  exit 1
fi

if [[ ! -w "$DEST_DIR" ]]; then
  echo "error: $DEST_DIR is not writable. Re-run with: sudo INSTALL_DIR=\"$DEST_DIR\" $0" >&2
  exit 1
fi

# Quit any running instance (from any location) so the bundle isn't busy when
# we replace it, and so the auto-update test starts from a clean launch.
pkill -f "$APP_NAME/Contents/" 2>/dev/null || true
pkill -f "$LEGACY_APP_NAME/Contents/" 2>/dev/null || true
sleep 1

echo "Installing to $DEST_APP ..."
rm -rf "$DEST_APP"
rm -rf "$LEGACY_DEST_APP"
# ditto preserves the code signature and extended attributes; cp -R can corrupt them.
ditto "$SOURCE_APP" "$DEST_APP"

# Local builds aren't quarantined, but strip it just in case so Gatekeeper
# doesn't block the launch.
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

if codesign --verify --deep --strict "$DEST_APP" >/dev/null 2>&1; then
  echo "Installed and signature verified: $DEST_APP"
else
  echo "warning: installed but signature verification failed: $DEST_APP" >&2
fi
