#!/bin/bash
# Собирает Embers.app через xcodegen + xcodebuild (то же, что ⌘B в Xcode)
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
xcodebuild -project Embers.xcodeproj -scheme Embers -configuration Release -derivedDataPath build build | tail -5
rm -rf Embers.app && cp -R build/Build/Products/Release/Embers.app .
echo "OK: $(pwd)/Embers.app"
