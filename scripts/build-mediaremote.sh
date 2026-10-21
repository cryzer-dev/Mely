#!/bin/zsh
# Builds MediaRemoteAdapter.framework (github.com/ungive/mediaremote-adapter, BSD-3) into
# build/mediaremote, without CMake: the framework is a handful of Objective-C files.
# build-app.sh bundles it with the Perl script; /usr/bin/perl loads it (task 5.1).
set -euo pipefail
cd "$(dirname "$0")/.."

COMMIT=0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd
OUT=build/mediaremote
FW=$OUT/MediaRemoteAdapter.framework
[[ -f $OUT/.commit && $(cat $OUT/.commit) == $COMMIT && -f $FW/MediaRemoteAdapter ]] && exit 0

SRC=$OUT/src
rm -rf $OUT && mkdir -p $SRC
curl -fsSL "https://codeload.github.com/ungive/mediaremote-adapter/tar.gz/$COMMIT" | tar -xz -C $SRC --strip-components 1

FILES=(adapter/env adapter/get adapter/globals adapter/keys adapter/now_playing adapter/repeat adapter/seek
       adapter/send adapter/shuffle adapter/speed adapter/stream adapter/test private/MediaRemote
       utility/Debounce utility/helpers)
SOURCES=()
for f in $FILES; do SOURCES+=($SRC/src/$f.m); done
mkdir -p $FW/Versions/A/Resources
xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -arch arm64 -mmacosx-version-min=15.0 -O2 \
  -I $SRC/include -I $SRC/src \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o $FW/Versions/A/MediaRemoteAdapter $SOURCES
cat > $FW/Versions/A/Resources/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
</dict></plist>
PLIST
ln -sfn A $FW/Versions/Current
ln -sfn Versions/Current/MediaRemoteAdapter $FW/MediaRemoteAdapter
ln -sfn Versions/Current/Resources $FW/Resources
cp $SRC/bin/mediaremote-adapter.pl $OUT/
cp $SRC/LICENSE $OUT/LICENSE
codesign --force --sign - $FW
echo $COMMIT > $OUT/.commit
echo "Built $FW"
