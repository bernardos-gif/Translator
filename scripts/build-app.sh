#!/usr/bin/env bash
# Builds dist/Translator.app (and, with --dmg, dist/Translator-<version>.dmg).
# Run on a Mac with Xcode or the Command Line Tools installed.
# Run scripts/fetch-tools.sh first to bundle winetricks, cabextract and DXVK.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="Translator"
DIST="dist"
APP="$DIST/$APP_NAME.app"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 1.0.0)}"
MAKE_DMG=false
[[ "${1:-}" == "--dmg" ]] && MAKE_DMG=true

echo "→ Building release binary (universal: Apple Silicon + Intel)…"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "→ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

if [[ -f Resources/AppIcon.png ]]; then
  echo "→ Creating app icon…"
  ICONSET="$DIST/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  cp Resources/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
  rm -rf "$ICONSET"
fi

if [[ -d build/Tools ]]; then
  echo "→ Bundling helper tools…"
  cp -R build/Tools "$APP/Contents/Resources/Tools"
else
  echo "  (no build/Tools; the app will download its helpers during setup)"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>app.translator.mac</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Translator. Wine is © the Wine project (LGPL).</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Windows Program</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array><string>exe</string><string>msi</string><string>bat</string><string>cmd</string><string>lnk</string></array>
            <key>LSItemContentTypes</key>
            <array><string>com.microsoft.windows-executable</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "→ Ad-hoc signing…"
if [[ -f "$APP/Contents/Resources/Tools/cabextract" ]]; then
  codesign --force --sign - "$APP/Contents/Resources/Tools/cabextract"
fi
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP"
echo "✓ Built $APP"

if $MAKE_DMG; then
  echo "→ Creating disk image…"
  DMG="$DIST/$APP_NAME-$VERSION.dmg"
  STAGE="$DIST/dmg"
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "✓ Built $DMG"
fi
