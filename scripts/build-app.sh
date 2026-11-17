#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/ModuleCache"
swift build --disable-sandbox -c release
app="$PWD/build/UniPDF.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/UniPDF "$app/Contents/MacOS/UniPDF"
cp Resources/Info.plist "$app/Contents/Info.plist"
# English comes from the source code, the other languages from their tables.
cp -R Resources/*.lproj "$app/Contents/Resources/"
swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset" "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
print "Done: $app"
