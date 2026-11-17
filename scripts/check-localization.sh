#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/ModuleCache"
# A separate build, so that every file is compiled again and reports its texts.
strings="$PWD/.build/localization/strings"
rm -rf "$strings" .build/localization/build
mkdir -p "$strings"
swift build --disable-sandbox -c release --build-path .build/localization/build \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$strings"
swift scripts/check-localization.swift "$strings" Resources/de.lproj/Localizable.strings
