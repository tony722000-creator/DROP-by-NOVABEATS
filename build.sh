#!/bin/bash
# Construit "DROP.app" et le .zip prêt pour une Release GitHub.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DROP"
EXEC="DROP"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

echo "▶︎ Compilation (release, Apple Silicon + Intel)…"
mkdir -p "$BUILD_DIR"
for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx14.0"
done
for BIN in "$EXEC" dkw-flp; do
    lipo -create \
        ".build/arm64-apple-macosx/release/$BIN" \
        ".build/x86_64-apple-macosx/release/$BIN" \
        -output "$BUILD_DIR/$BIN"
done
codesign --force -s - "$BUILD_DIR/dkw-flp"

echo "▶︎ Assemblage de l'app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$EXEC" "$APP/Contents/MacOS/$EXEC"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Branding/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Branding/drop-logo.png "$APP/Contents/Resources/drop-logo.png"
# Images et vidéos de la pédale (Branding/ui)
mkdir -p "$APP/Contents/Resources/ui"
cp Branding/ui/*.png Branding/ui/*.jpg Branding/ui/*.mp4 "$APP/Contents/Resources/ui/"

echo "▶︎ Signature ad-hoc…"
codesign --force --deep -s - "$APP"

echo "▶︎ Création du .zip…"
ZIP="$BUILD_DIR/DROP-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▶︎ Création du .dmg…"
DMG="$BUILD_DIR/DROP-$VERSION.dmg"
STAGE="$BUILD_DIR/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "DROP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✅ Terminé : $APP"
echo "✅ Installeur : $DMG"
echo "✅ Archive : $ZIP"
