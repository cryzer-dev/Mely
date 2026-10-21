#!/bin/zsh
# Writes build/appcast.xml for Sparkle: one item, the given dmg, signed with Mely's EdDSA key.
# Usage: scripts/make-appcast.sh <Mely-X.Y.Z.dmg> <release notes .html> <download URL> <release page URL>
# The private key comes from SPARKLE_ED_KEY (CI secret) or, locally, from the keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
DMG=$1 NOTES=$2 URL=$3 PAGE=$4
TOOLS=.build/artifacts/sparkle/Sparkle/bin
[[ -x $TOOLS/sign_update ]] || swift package resolve >/dev/null

# The version is read from the app inside the image.
MNT=$(mktemp -d)
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "$DMG"
PLIST="$MNT/Mely.app/Contents/Info.plist"
SHORT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")
MIN=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$PLIST")
hdiutil detach -quiet "$MNT"

if [[ -n ${SPARKLE_ED_KEY:-} ]]; then
  SIGNATURE=$(print -rn -- "$SPARKLE_ED_KEY" | $TOOLS/sign_update --ed-key-file - "$DMG")
else
  SIGNATURE=$($TOOLS/sign_update --account mely "$DMG")
fi

cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Mely</title>
    <link>$PAGE</link>
    <language>ru</language>
    <item>
      <title>Mely $SHORT</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$SHORT</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$PAGE</sparkle:fullReleaseNotesLink>
      <description><![CDATA[$(cat "$NOTES")]]></description>
      <enclosure url="$URL" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
echo "Wrote build/appcast.xml for $SHORT ($BUILD)"
