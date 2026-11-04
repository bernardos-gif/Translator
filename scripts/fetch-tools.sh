#!/usr/bin/env bash
# Prepares the helper tools bundled inside Translator.app (build/Tools):
#   - winetricks  : installs Windows components (Visual C++, .NET, DirectX, fonts…)
#   - cabextract  : unpacks Microsoft .cab archives (winetricks needs it); built universal
#   - dxvk/       : DirectX 9/10/11 → Vulkan (→ Metal via MoltenVK) for games
# Run on macOS with the Xcode command line tools installed.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="build/Tools"
WINETRICKS_TAG="${WINETRICKS_TAG:-20260125}"
CABEXTRACT_VERSION="${CABEXTRACT_VERSION:-1.11}"
DXVK_URL="${DXVK_URL:-https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz}"

rm -rf "$OUT" build/work
mkdir -p "$OUT" build/work

echo "→ winetricks $WINETRICKS_TAG"
curl -fsSL -o "$OUT/winetricks" "https://raw.githubusercontent.com/Winetricks/winetricks/$WINETRICKS_TAG/src/winetricks"
chmod +x "$OUT/winetricks"
head -1 "$OUT/winetricks" | grep -q bash

echo "→ cabextract $CABEXTRACT_VERSION (universal)"
curl -fsSL -o build/work/cabextract.tar.gz "https://www.cabextract.org.uk/cabextract-$CABEXTRACT_VERSION.tar.gz"
tar -xzf build/work/cabextract.tar.gz -C build/work
(
  cd "build/work/cabextract-$CABEXTRACT_VERSION"
  CFLAGS="-O2 -arch arm64 -arch x86_64 -mmacosx-version-min=13.0" \
    ./configure --disable-dependency-tracking >/dev/null
  make -j4 >/dev/null
)
cp "build/work/cabextract-$CABEXTRACT_VERSION/cabextract" "$OUT/cabextract"
lipo -info "$OUT/cabextract"

echo "→ DXVK for macOS"
curl -fsSL -o build/work/dxvk.tar.gz "$DXVK_URL"
mkdir -p build/work/dxvk
tar -xzf build/work/dxvk.tar.gz -C build/work/dxvk
DXVK_DIR="$(dirname "$(find build/work/dxvk -type d -name x64 | head -1)")"
mkdir -p "$OUT/dxvk"
cp -R "$DXVK_DIR/x64" "$DXVK_DIR/x32" "$OUT/dxvk/"
ls "$OUT/dxvk/x64"

rm -rf build/work
echo "✓ Tools ready in $OUT"
