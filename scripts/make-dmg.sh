#!/bin/zsh
# Builds build/Mely-<version>.dmg (task 7.8): the app, a link to /Applications, a background
# with an arrow, icons placed by Finder. Needs only hdiutil, tiffutil and osascript.
# Usage: scripts/make-dmg.sh [--skip-build] [--ci | --save-layout]
#   --save-layout  after Finder lays the window out, keeps its .DS_Store and the background
#                  in Resources/dmg (run once locally when the background changes)
#   --ci           no Finder (GitHub runners): uses what --save-layout kept
set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_BUILD=0; CI_MODE=0; SAVE_LAYOUT=0
for arg in "$@"; do
  case $arg in
    --skip-build) SKIP_BUILD=1 ;;
    --ci) CI_MODE=1 ;;
    --save-layout) SAVE_LAYOUT=1 ;;
  esac
done
(( SKIP_BUILD )) || scripts/build-app.sh
APP=build/Mely.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $APP/Contents/Info.plist)
VOLUME="Mely"
DMG=build/Mely-$VERSION.dmg
WORK=build/dmg
# The writable image sits outside the project: Finder writes its path into .DS_Store, which
# --save-layout keeps in the repo, so it must not carry a home folder.
RW=/private/tmp/mely-dmg/Mely-rw.dmg
mkdir -p ${RW:h}
rm -rf $WORK $DMG $RW
mkdir -p $WORK/stage/.background

# Background at 1x and 2x, joined into one HiDPI TIFF.
if (( CI_MODE )); then
  cp Resources/dmg/background.tiff $WORK/stage/.background/background.tiff
else
  swift run -c release mely-snapshots --dmg-background $WORK >/dev/null
  tiffutil -cathidpicheck $WORK/background.png $WORK/background@2x.png -out $WORK/stage/.background/background.tiff >/dev/null 2>&1
fi

cp -R $APP $WORK/stage/Mely.app
ln -s /Applications $WORK/stage/Applications

# A writable image first, so Finder can lay the window out.
hdiutil create -quiet -srcfolder $WORK/stage -volname $VOLUME -fs HFS+ -format UDRW -ov $RW
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen $RW | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT="/Volumes/$VOLUME"
sleep 1

# Window 660×420, big icons: Mely left, «Программы» right of the arrow. Finder may ask once
# for permission to be controlled; without it the image still works, just unstyled.
if (( CI_MODE )); then
  cp Resources/dmg/DS_Store "$MOUNT/.DS_Store"
elif ! osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 568}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Mely.app" of container window to {170, 215}
    set position of item "Applications" of container window to {490, 215}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
then
  echo "Finder did not lay the window out (no Automation permission?): the dmg works, unstyled." >&2
elif (( SAVE_LAYOUT )); then
  sleep 1
  mkdir -p Resources/dmg
  cp "$MOUNT/.DS_Store" Resources/dmg/DS_Store
  cp $WORK/stage/.background/background.tiff Resources/dmg/background.tiff
  echo "Saved the window layout in Resources/dmg"
fi

chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync
hdiutil detach -quiet $DEVICE
hdiutil convert -quiet $RW -format UDZO -imagekey zlib-level=9 -o $DMG
rm -f $RW
# Older installers go; the dmg is now the one place the app ships from.
for old in build/Mely-*.dmg(N); do [[ $old == $DMG ]] || rm -f $old; done
rm -rf $WORK
echo "Built $DMG ($(du -h $DMG | cut -f1))"
