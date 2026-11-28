#!/usr/bin/env bash
# Builds SunPad Next.app for Apple silicon Macs on the decompilation engine
# (docs/DECOMP-ENGINE-PLAN.md, E5.1). The engine is the game's decompiled
# code: the app is for this Mac only and is never published.
# usage: package-macos-next.sh [OUTPUT_APP]
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT="${1:-$ROOT/build-macos/SunPad Next.app}"
ENGINE="$ROOT/ref/sms-pc-port"
[[ -f "$ENGINE/build.sh" ]] || { echo "ref/sms-pc-port is missing; run scripts/bootstrap-dependencies.sh" >&2; exit 1; }

# The engine's own build: native arm64 with its pointer pass, SDL2 and MoltenVK it fetches and checks.
(cd "$ENGINE" && SMS_ARCH=arm64 SMS_STANDALONE=0 ./build.sh)
BUILT="$ENGINE/build/macos-arm64"
for part in sms SDL2.framework libMoltenVK.dylib; do
  [[ -e "$BUILT/$part" ]] || { echo "the engine build left no $part" >&2; exit 1; }
done

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sunpad-next-mac.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/SunPad Next.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$ROOT/apple/macos/next/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/apple/macos/next/SunPadNext" "$APP/Contents/MacOS/SunPadNext"
chmod +x "$APP/Contents/MacOS/SunPadNext"
cp "$BUILT/sms" "$APP/Contents/MacOS/sms"
cp -R "$BUILT/SDL2.framework" "$APP/Contents/Frameworks/"
cp "$BUILT/libMoltenVK.dylib" "$APP/Contents/Frameworks/"
cp "$ROOT/apple/macos/next/bindings.txt" "$APP/Contents/Resources/bindings.txt"
cp "$ROOT/apple/macos/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
xcrun clang++ -std=c++17 -fobjc-arc -O2 -mmacosx-version-min=14.0 -I "$ROOT/apple/shared" \
  "$ROOT/apple/macos/next/sunpad-saves.mm" "$ROOT/apple/shared/SunPadEngineSaves.mm" \
  "$ROOT/apple/shared/SunPadSaveTransfer.mm" -framework Foundation -o "$APP/Contents/MacOS/sunpad-saves"

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$(dirname -- "$OUTPUT")"
rm -rf "$OUTPUT"
mv "$APP" "$OUTPUT"
echo "$OUTPUT"
