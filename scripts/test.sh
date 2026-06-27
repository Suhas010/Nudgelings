#!/bin/zsh
# Swift Testing ships with Command Line Tools but isn't on the default search path.
set -e
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
cd "$(dirname "$0")/.."
swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
