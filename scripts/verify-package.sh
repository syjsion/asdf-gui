#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <app-path> <dmg-path>" >&2
  exit 64
fi

APP_PATH="$1"
DMG_PATH="$2"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/asdf-gui"
ZH_LOCALIZATION="$APP_PATH/Contents/Resources/zh-Hans.lproj/Localizable.strings"

[[ -d "$APP_PATH" ]] || { echo "missing app bundle: $APP_PATH" >&2; exit 66; }
[[ -f "$INFO_PLIST" ]] || { echo "missing Info.plist" >&2; exit 66; }
[[ -x "$EXECUTABLE" ]] || { echo "missing executable" >&2; exit 66; }
[[ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]] || { echo "missing AppIcon.icns" >&2; exit 66; }
[[ -f "$ZH_LOCALIZATION" ]] || { echo "missing Simplified Chinese localization" >&2; exit 66; }
[[ -f "$DMG_PATH" ]] || { echo "missing DMG: $DMG_PATH" >&2; exit 66; }

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"
PACKAGE_TYPE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$INFO_PLIST")"

[[ "$BUNDLE_ID" == "io.github.syjsion.asdf-gui" ]] || { echo "unexpected bundle id: $BUNDLE_ID" >&2; exit 65; }
[[ "$MIN_OS" == "14.0" ]] || { echo "unexpected minimum macOS: $MIN_OS" >&2; exit 65; }
[[ "$PACKAGE_TYPE" == "APPL" ]] || { echo "unexpected package type: $PACKAGE_TYPE" >&2; exit 65; }

grep -q '"Projects" = "项目";' "$ZH_LOCALIZATION" || { echo "Chinese localization table is incomplete" >&2; exit 65; }

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
hdiutil verify "$DMG_PATH"
file "$EXECUTABLE"
