#!/usr/bin/env bash
# Builds Translator.app into ./dist. Run on a Mac with Xcode or the Command Line Tools installed.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="Translator"
DIST="dist"
APP="$DIST/$APP_NAME.app"
VERSION="${VERSION:-1.0.0}"

echo "→ Building release binary (universal: Apple Silicon + Intel)…"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "→ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>app.translator.mac</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
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
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"
echo "  Open it with:  open \"$APP\""
echo "  Install it:    cp -R \"$APP\" /Applications/"
