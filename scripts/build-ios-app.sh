#!/usr/bin/env bash
# Build the publishable SunPad app: no game code. PadMint adds the module
# translated from the player's own disc (scripts/package-ios.sh PUBLISHED.ipa).
# Usage: scripts/build-ios-app.sh [OUTPUT.ipa]
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/version.json")"
build="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$ROOT/version.json")"
OUTPUT="${1:-$ROOT/artifacts/SunPad-v$version-ios-unsigned.ipa}"
derived="$(mktemp -d /tmp/sunpad-app.XXXXXX)"
trap 'rm -rf "$derived"' EXIT

SUNPAD_CORE_ONLY=1 "$ROOT/scripts/ios-build-core-device.sh"
"$ROOT/scripts/ios-provision-device.sh"   # merge the fresh core into libSunPadCore.a
xcodebuild -project "$ROOT/SunPad.xcodeproj" -scheme SunPad -configuration Release \
  -destination generic/platform=iOS -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" build
"$ROOT/scripts/package-ios.sh" "$derived/Build/Products/Release-iphoneos/SunPad.app" none "$OUTPUT"
