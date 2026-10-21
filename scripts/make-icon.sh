#!/bin/zsh
# Renders Resources/AppIcon.icns from MelyAppIcon (Sources/MelyUI/Brand/MelyLogo.swift).
# Run after changing the logo; build-app.sh copies the .icns into the bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swift run mely-snapshots --app-icon $TMP/AppIcon.iconset
iconutil -c icns $TMP/AppIcon.iconset -o Resources/AppIcon.icns
rm -rf $TMP
echo "Wrote Resources/AppIcon.icns"
