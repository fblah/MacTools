#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/DMonte Toolbox.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
SYSTEM_MONITOR_APP_DIR="$HELPERS_DIR/DMonte System Monitor.app"
SYSTEM_MONITOR_CONTENTS_DIR="$SYSTEM_MONITOR_APP_DIR/Contents"
SYSTEM_MONITOR_MACOS_DIR="$SYSTEM_MONITOR_CONTENTS_DIR/MacOS"
SYSTEM_MONITOR_INFO_PLIST="$SYSTEM_MONITOR_CONTENTS_DIR/Info.plist"
VERSION="${VERSION_OVERRIDE:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)}"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$SYSTEM_MONITOR_MACOS_DIR"

cp "$ROOT_DIR/.build/release/DMonte" "$MACOS_DIR/DMonte"
cp "$ROOT_DIR/.build/release/DMonteSystemMonitor" "$SYSTEM_MONITOR_MACOS_DIR/DMonteSystemMonitor"
cp "$ROOT_DIR/Packaging/Info.plist" "$INFO_PLIST"
cp "$ROOT_DIR/Packaging/SystemMonitorInfo.plist" "$SYSTEM_MONITOR_INFO_PLIST"

if [[ -d "$ROOT_DIR/.build/release/Sparkle.framework" ]]; then
  cp -R "$ROOT_DIR/.build/release/Sparkle.framework" "$FRAMEWORKS_DIR/"
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/DMonte" 2>/dev/null || true

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$SYSTEM_MONITOR_INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$SYSTEM_MONITOR_INFO_PLIST"

if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST"
fi

codesign --force --deep --sign - "$APP_DIR"

echo "Created $APP_DIR"
