#!/usr/bin/env bash
# The auditor rejects a player's copy whose engine is an unrelated library.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
APP="$TEMP/Payload/SunPad.app"
mkdir -p "$APP/Frameworks"
printf 'int unrelated_library(void) { return 0; }\n' | \
  xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -x c -dynamiclib - \
  -o "$APP/Frameworks/libsms_embed.dylib"
cp "$APP/Frameworks/libsms_embed.dylib" "$APP/SunPad"
cp "$ROOT/LICENSE" "$APP/LICENSE"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/THIRD_PARTY_NOTICES.md"
(cd "$TEMP" && zip -qr fixture.ipa Payload)
if "$ROOT/scripts/audit-ios-package.sh" "$TEMP/fixture.ipa" > "$TEMP/result" 2>&1; then
  echo "Audit accepted an unrelated engine" >&2; exit 1
fi
grep -Fq 'iOS package audit failed' "$TEMP/result"
echo "Unrelated iOS engine correctly rejected"
