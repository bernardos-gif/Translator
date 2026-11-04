#!/usr/bin/env bash
# Builds dist/VPN.app (and, with --dmg, dist/VPN-<version>.dmg).
# Run on a Mac with Xcode or the Command Line Tools installed.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="VPN"
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

# The server script travels inside the app and is uploaded to the server on connect.
cp vpn.sh "$APP/Contents/Resources/vpn.sh"

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

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>app.vpn.mac</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>VPN. WireGuard is a registered trademark of Jason A. Donenfeld.</string>
</dict>
</plist>
PLIST

echo "→ Ad-hoc signing…"
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
