#!/bin/zsh
# Run the PatterCore unit tests (`swift test`), including on machines that have
# only the Command Line Tools.
#
#   ./scripts/test.sh [swift test args...]
#
# Without Xcode, SwiftPM can't find Testing.framework on its own: it ships in
# the CLT but outside the default search paths. When the CLT are the selected
# developer dir, point the compiler and linker at it and add rpaths for the
# framework and its lib_TestingInterop.dylib. With Xcode selected (CI), this is
# plain `swift test`.

set -euo pipefail

repo="${0:A:h:h}"
cd "$repo"

dev="$(xcode-select -p 2>/dev/null || true)"
frameworks="$dev/Library/Developer/Frameworks"
libs="$dev/Library/Developer/usr/lib"

flags=()
if [[ "$dev" == */CommandLineTools && -d "$frameworks/Testing.framework" ]]; then
  flags=(
    -Xswiftc -F -Xswiftc "$frameworks"
    -Xlinker -F -Xlinker "$frameworks"
    -Xlinker -rpath -Xlinker "$frameworks"
    -Xlinker -rpath -Xlinker "$libs"
  )
fi

exec swift test "${flags[@]}" "$@"
