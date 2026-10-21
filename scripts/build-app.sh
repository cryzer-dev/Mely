#!/bin/zsh
# Builds build/Mely.app and signs it with the "Mely Dev" identity (scripts/make-dev-cert.sh).
# Usage: scripts/build-app.sh [--debug] [--install] [--ad-hoc]
#   --install  puts it in /Applications (the one copy: an older one in ~/Applications is removed)
#   --ad-hoc   signs without an identity (CI checks of pull requests)
# The version comes from version.txt (kept by release-please); the build number is
# 100 + the commit count, so it only grows. Uncommitted changes make it "X.Y.Z-dev".
# MELY_SIGN_IDENTITY and MELY_KEYCHAIN override the identity and keychain (the release CI).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
INSTALL=0
ADHOC=0
for arg in "$@"; do
  case $arg in
    --debug) CONFIG=debug ;;
    --install) INSTALL=1 ;;
    --ad-hoc) ADHOC=1 ;;
  esac
done
IDENTITY=${MELY_SIGN_IDENTITY:-"Mely Dev"}
KEYCHAIN_ARGS=()
[[ -n ${MELY_KEYCHAIN:-} ]] && KEYCHAIN_ARGS=(--keychain "$MELY_KEYCHAIN")

VERSION=$(tr -d ' \n' < version.txt)
BUILD=100
if git rev-parse --git-dir >/dev/null 2>&1; then
  BUILD=$(( 100 + $(git rev-list --count HEAD 2>/dev/null || echo 0) ))
  [[ -n $(git status --porcelain -- Sources Resources Package.swift 2>/dev/null) ]] && VERSION="$VERSION-dev"
fi

# Build products stay out of Spotlight and Launchpad: only the installed Mely shows there.
mkdir -p build && touch build/.metadata_never_index
swift build -c $CONFIG --product Mely
swift build -c $CONFIG --product nc-hook
BIN=$(swift build -c $CONFIG --show-bin-path)

APP=build/Mely.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Helpers $APP/Contents/Resources $APP/Contents/Frameworks
cp Resources/Info.plist $APP/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" \
  $APP/Contents/Info.plist
cp Resources/AppIcon.icns $APP/Contents/Resources/AppIcon.icns
cp LICENSE THIRD_PARTY_NOTICES.md $APP/Contents/Resources/
cp $BIN/Mely $APP/Contents/MacOS/Mely
cp $BIN/nc-hook $APP/Contents/Helpers/nc-hook
# Sparkle: the framework next to the app's code, found through the rpath. Mely is not
# sandboxed, so Sparkle's XPC services are not needed.
ditto $BIN/Sparkle.framework $APP/Contents/Frameworks/Sparkle.framework
rm -rf $APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices $APP/Contents/Frameworks/Sparkle.framework/XPCServices
otool -l $APP/Contents/MacOS/Mely | grep -q "@executable_path/../Frameworks" ||
  install_name_tool -add_rpath @executable_path/../Frameworks $APP/Contents/MacOS/Mely
# Now Playing adapter (task 5.1): run by /usr/bin/perl, so bundled as a resource, not linked.
scripts/build-mediaremote.sh
mkdir -p $APP/Contents/Resources/MediaRemote
cp build/mediaremote/mediaremote-adapter.pl $APP/Contents/Resources/MediaRemote/
cp -R build/mediaremote/MediaRemoteAdapter.framework $APP/Contents/Resources/MediaRemote/
# Mely's own sounds (task 7.4, scripts/make-sounds.py).
cp -R Resources/Sounds $APP/Contents/Resources/
# SwiftPM resource bundles, if any target has resources.
for bundle in $BIN/*.bundle(N); do cp -R $bundle $APP/Contents/Resources/; done

# Inside out: Sparkle's helpers, the framework, the hook relay, then the app.
if (( ADHOC )); then
  SIGN=(codesign --force --options runtime --timestamp=none -s -)
else
  if ! security find-certificate -c "$IDENTITY" ${MELY_KEYCHAIN:-} >/dev/null 2>&1; then
    echo "No “$IDENTITY” identity: run scripts/make-dev-cert.sh first." >&2
    exit 1
  fi
  SIGN=(codesign --force --options runtime --timestamp=none -s "$IDENTITY" "${KEYCHAIN_ARGS[@]}")
fi
SPARKLE=$APP/Contents/Frameworks/Sparkle.framework
$SIGN $SPARKLE/Versions/B/Autoupdate
$SIGN $SPARKLE/Versions/B/Updater.app
$SIGN $SPARKLE
$SIGN $APP/Contents/Helpers/nc-hook
$SIGN --entitlements Resources/Mely.entitlements $APP
codesign --verify --strict $APP
echo "Built $APP $VERSION ($BUILD, $CONFIG)"

if (( INSTALL )); then
  pkill -x Mely 2>/dev/null || true
  rm -rf /Applications/Mely.app ~/Applications/Mely.app
  cp -R $APP /Applications/Mely.app
  echo "Installed /Applications/Mely.app"
fi
