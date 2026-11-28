#!/usr/bin/env bash
# Builds the published SunPad app for iPhone and iPad: the app, MoltenVK and no
# game code. PadMint adds the engine it builds on the player's Mac
# (scripts/package-ios.sh PUBLISHED.ipa ENGINE).
# usage: scripts/build-ios-app.sh [OUTPUT.ipa]
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/version.json")"
build="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$ROOT/version.json")"
OUTPUT="${1:-$ROOT/artifacts/SunPad-v$version-ios-unsigned.ipa}"
derived="$(mktemp -d "${TMPDIR:-/tmp}/sunpad-app.XXXXXX")"
trap 'rm -rf "$derived"' EXIT

"$ROOT/scripts/fetch-moltenvk.sh"
xcodebuild -project "$ROOT/SunPad.xcodeproj" -scheme SunPad -configuration Release \
  -destination generic/platform=iOS -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO SUNPAD_EMBED_ENGINE=NO MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" build
"$ROOT/scripts/package-ios.sh" "$derived/Build/Products/Release-iphoneos/SunPad.app" none "$OUTPUT"
