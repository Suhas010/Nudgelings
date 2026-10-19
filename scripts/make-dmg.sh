#!/bin/zsh
# Builds "dist/Nudgelings-<version>.dmg": a drag-to-Applications window with the crew's own background art.
#
#   scripts/make-dmg.sh
#
# Without an Apple Developer ID the app and DMG are ad-hoc signed: fine for you and friends, but
# Gatekeeper asks first-time users to approve it (see README › Install). To ship a DMG that opens
# with no warning, set both of these and the script signs, notarises and staples:
#
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE=<profile saved with `xcrun notarytool store-credentials`>
set -e
cd "$(dirname "$0")/.."

NAME=Nudgelings
APP="dist/$NAME.app"
scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/$NAME-$VERSION.dmg"

if [[ -n "$DEVELOPER_ID" ]]; then
  echo "Signing with $DEVELOPER_ID (hardened runtime)"
  codesign --force --deep --options runtime --timestamp -s "$DEVELOPER_ID" "$APP"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Background art, rendered by the app itself at 1× and 2×, merged into one Retina-aware TIFF.
"$APP/Contents/MacOS/Drip" --dmg-background "$STAGE/.background/bg"
tiffutil -cathidpicheck "$STAGE/.background/bg.png" "$STAGE/.background/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null
rm "$STAGE/.background/"bg*.png

# A writable image first, so Finder can save the window layout into it.
hdiutil detach "/Volumes/$NAME" -quiet 2>/dev/null || true
RW="$WORK/rw.dmg"
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')
MNT="/Volumes/$NAME"

# Window layout. Icon centres match the art (Snapshots.dmgBackground). The first run asks to let
# your terminal control Finder; if that's declined the DMG still works, just without the styling.
if ! osascript <<EOF
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 860, 628}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "$NAME.app" of container window to {170, 215}
    set position of item "Applications" of container window to {490, 215}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
then
  echo "⚠︎  Finder layout skipped. Allow your terminal to control Finder (System Settings › Privacy & Security › Automation) for the styled window."
fi

# The app icon doubles as the mounted disk's icon (Finder sidebar, desktop). It lives inside the
# image, so it survives downloads. Added after the layout step: Finder removes it while laying out.
cp "$APP/Contents/Resources/AppIcon.icns" "$MNT/.VolumeIcon.icns"
SetFile -a C "$MNT"

chmod -Rf go-w "$MNT" 2>/dev/null || true
sync
hdiutil detach "$DEV" -quiet
rm -f "$DMG"
hdiutil convert "$RW" -quiet -format UDZO -imagekey zlib-level=9 -o "$DMG"

# The .dmg file's own Finder icon. Stored in the file's metadata, so it shows on this Mac and in
# zips/AirDrop, but web downloads arrive with the generic disk icon (the mounted disk keeps its icon).
osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSWorkspace.sharedWorkspace.setIconForFileOptions(\$.NSImage.alloc.initWithContentsOfFile('$PWD/$APP/Contents/Resources/AppIcon.icns'), '$PWD/$DMG', 0)" >/dev/null

if [[ -n "$DEVELOPER_ID" ]]; then
  codesign --force --timestamp -s "$DEVELOPER_ID" "$DMG"
  if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

# For sharing: a checksum and a ready-to-paste download block for a website.
FILE=$(basename "$DMG")
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "$SHA  $FILE" > "$DMG.sha256"
SIZE=$(du -h "$DMG" | cut -f1 | tr -d ' ')
sed -e "s|{{FILE}}|$FILE|g" -e "s|{{VERSION}}|$VERSION|g" -e "s|{{SIZE}}|${SIZE}B|g" -e "s|{{SHA}}|$SHA|g" \
  scripts/download-snippet.html > dist/download-snippet.html

# Keep the build copy from competing with an installed one when Nudgelings is opened by name.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true

echo "Built $DMG ($SIZE, $(lipo -archs "$APP/Contents/MacOS/Drip"))"
echo "SHA-256 $SHA"
echo "Website block: dist/download-snippet.html"
