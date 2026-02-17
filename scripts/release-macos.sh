#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then
  set -a
  source "$ROOT/.env"
  set +a
fi
PROJECT="${PROJECT:-$ROOT/ios/spackle/spackle.xcodeproj}"
SCHEME="${SCHEME:-spackle}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_DIR/$SCHEME.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$BUILD_DIR/export}"
DIST_PATH="${DIST_PATH:-$BUILD_DIR/dist}"
APP_NAME="${APP_NAME:-Spackle}"
PACKAGE_FORMAT="${PACKAGE_FORMAT:-all}"
TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ "$PACKAGE_FORMAT" != "all" && "$PACKAGE_FORMAT" != "dmg" && "$PACKAGE_FORMAT" != "zip" ]]; then
  echo "Invalid PACKAGE_FORMAT: $PACKAGE_FORMAT (expected: all|dmg|zip)" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR" "$DIST_PATH"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

EXPORT_OPTIONS="$(mktemp "$BUILD_DIR/export-options.XXXXXX.plist")"
trap 'rm -f "$EXPORT_OPTIONS"' EXIT

cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
EOF

if [[ -n "$TEAM_ID" ]]; then
  /usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$EXPORT_OPTIONS"
fi

echo "==> Archiving ($SCHEME, $CONFIGURATION)"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH"

echo "==> Exporting signed app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -type d -name "*.app" | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "No .app found in $EXPORT_PATH" >&2
  exit 1
fi

ZIP_PATH="$DIST_PATH/$APP_NAME.zip"
DMG_PATH="$DIST_PATH/$APP_NAME.dmg"

if [[ -n "$NOTARY_PROFILE" ]]; then
  echo "==> Zipping app for notarization"
  NOTARY_ZIP="$BUILD_DIR/$APP_NAME-notarize.zip"
  rm -f "$NOTARY_ZIP"
  ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
  echo "==> Notarizing app"
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$NOTARY_ZIP"
  echo "==> Stapling app"
  xcrun stapler staple "$APP_PATH"
fi

if [[ "$PACKAGE_FORMAT" == "all" || "$PACKAGE_FORMAT" == "zip" ]]; then
  echo "==> Building zip: $ZIP_PATH"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
fi

if [[ "$PACKAGE_FORMAT" == "all" || "$PACKAGE_FORMAT" == "dmg" ]]; then
  echo "==> Building dmg: $DMG_PATH"
  DMG_ROOT="$BUILD_DIR/dmg-root"
  DMG_RW="$BUILD_DIR/$APP_NAME-rw.dmg"
  rm -rf "$DMG_ROOT" "$DMG_PATH" "$DMG_RW"
  mkdir -p "$DMG_ROOT"
  cp -R "$APP_PATH" "$DMG_ROOT/"
  ln -s /Applications "$DMG_ROOT/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDRW "$DMG_RW"
  rm -rf "$DMG_ROOT"
  hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_PATH"
  rm -f "$DMG_RW"

  if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "==> Notarizing dmg"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling dmg"
    xcrun stapler staple "$DMG_PATH"
  fi
fi

echo "==> Done"
echo "App: $APP_PATH"
if [[ -f "$ZIP_PATH" ]]; then
  echo "Zip: $ZIP_PATH"
fi
if [[ -f "$DMG_PATH" ]]; then
  echo "DMG: $DMG_PATH"
fi
