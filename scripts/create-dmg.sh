#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <app-path> <output-dmg>" >&2
  exit 64
fi

APP_PATH="$1"
OUTPUT_DMG="$2"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VOLUME_NAME="${VOLUME_NAME:-asdf GUI}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "app bundle not found: $APP_PATH" >&2
  exit 66
fi

mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG"

STAGING_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUTPUT_DMG"
  codesign --verify --verbose=2 "$OUTPUT_DMG"
fi

hdiutil verify "$OUTPUT_DMG"
printf '%s\n' "$OUTPUT_DMG"
