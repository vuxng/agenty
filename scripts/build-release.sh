#!/bin/bash
# Build an ad-hoc signed, arm64-only Release zip: scripts/build-release.sh <version>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <version>   (e.g. $0 0.1.0)" >&2
  exit 1
fi

VERSION="$1"
cd "$(dirname "$0")/.."

xcodegen generate

xcodebuild -project Agenty.xcodeproj -scheme Agenty -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  MARKETING_VERSION="$VERSION" build

APP="build/DerivedData/Build/Products/Release/Agenty.app"
ZIP="build/Agenty-$VERSION-arm64.zip"

codesign --force --deep --options runtime --sign - "$APP"
codesign --verify --strict "$APP"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/Agenty")"
if [ "$ARCHS" != "arm64" ]; then
  echo "Expected arm64 only, got: $ARCHS" >&2
  exit 1
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Created $ZIP"
