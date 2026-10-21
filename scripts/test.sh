#!/bin/zsh
# Runs the test suite. With only the Command Line Tools installed, Swift Testing lives
# outside SwiftPM's default search paths, so pass them explicitly; with Xcode this is plain `swift test`.
set -euo pipefail
cd "$(dirname "$0")/.."
# NCHookProcessTests runs the real relay binary: build it first.
swift build --product nc-hook >/dev/null
DEV=/Library/Developer/CommandLineTools/Library/Developer
if [[ ! -d /Applications/Xcode.app && -d $DEV/Frameworks/Testing.framework ]]; then
  exec swift test \
    -Xswiftc -F -Xswiftc $DEV/Frameworks \
    -Xlinker -F -Xlinker $DEV/Frameworks \
    -Xlinker -rpath -Xlinker $DEV/Frameworks \
    -Xlinker -rpath -Xlinker $DEV/usr/lib "$@"
fi
exec swift test "$@"
