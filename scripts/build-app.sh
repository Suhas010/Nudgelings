#!/bin/zsh
# Builds "dist/Nudgelings.app" (release, universal, ad-hoc signed). Usage: scripts/build-app.sh
set -e
cd "$(dirname "$0")/.."
# Universal: Apple Silicon + Intel, built separately and merged.
ARM=arm64-apple-macosx14.0
INTEL=x86_64-apple-macosx14.0
swift build -c release --triple $ARM
swift build -c release --triple $INTEL
BIN=$(swift build -c release --triple $ARM --show-bin-path)
BIN_INTEL=$(swift build -c release --triple $INTEL --show-bin-path)
APP="dist/Nudgelings.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$BIN/Drip" "$BIN_INTEL/Drip" -output "$APP/Contents/MacOS/Drip"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Fonts" && cp Resources/Fonts/* "$APP/Contents/Resources/Fonts/"

# App icon, rendered by the app itself.
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
"$BIN/Drip" --icon "$ICONSET/icon_512x512@2x.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep -s - "$APP"
echo "Built $APP"
