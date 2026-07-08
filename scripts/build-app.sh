#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ActionRing"
APP_DISPLAY_NAME="Action Ring"
VERSION="$(tr -d '\n' < "$ROOT_DIR/VERSION")"
SHORT_VERSION="${VERSION#v}"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_TEMPLATE="$ROOT_DIR/bundle/Info.plist.template"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
EXECUTABLE_PATH="$BUILD_DIR/$APP_NAME"
ICON_SCRIPT="$ROOT_DIR/scripts/build-icon.sh"
ICON_PATH="$ROOT_DIR/bundle/AppIcon.icns"

echo "Building $APP_DISPLAY_NAME $VERSION..."
if [[ -f "$ICON_SCRIPT" ]]; then
  zsh "$ICON_SCRIPT"
fi

swift build -c release --product "$APP_NAME" --package-path "$ROOT_DIR"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Missing built executable: $EXECUTABLE_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
cp "$INFO_TEMPLATE" "$INFO_PLIST"

if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SHORT_VERSION" "$INFO_PLIST"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo
echo "Built app bundle:"
echo "  $APP_DIR"
echo
echo "Open it with:"
echo "  open \"$APP_DIR\""
