#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_NAME="asdf GUI"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
MACOS_DIR="$APP_DIR/Contents/MacOS"
ICONSET_DIR="$OUTPUT_DIR/AppIcon.iconset"

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$RESOURCES_DIR" "$MACOS_DIR"

cd "$ROOT_DIR"
swift build --configuration release --product asdf-gui
BIN_DIR="$(swift build --configuration release --show-bin-path)"
cp "$BIN_DIR/asdf-gui" "$MACOS_DIR/asdf-gui"
chmod +x "$MACOS_DIR/asdf-gui"
strip -x "$MACOS_DIR/asdf-gui" || true

cp "$ROOT_DIR/packaging/Info.plist" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"

python3 "$ROOT_DIR/scripts/generate-app-icon.py" "$ICONSET_DIR"
iconutil --convert icns "$ICONSET_DIR" --output "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign \
    --force \
    --options runtime \
    --entitlements "$ROOT_DIR/packaging/asdf-gui.entitlements" \
    --sign - \
    "$APP_DIR"
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$ROOT_DIR/packaging/asdf-gui.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

printf '%s\n' "$APP_DIR"
