#!/usr/bin/env bash
# Packages SunPad for iPhone and iPad.
# usage: package-ios.sh APP ENGINE|none [OUTPUT.ipa]
#   APP     a built SunPad.app, or the published SunPad IPA
#   ENGINE  the player's libsms_embed.dylib, or "none" for the published app,
#           which carries no game code
# Both are audited; the IPA is unsigned and must be signed before installing.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="${1:?usage: package-ios.sh APP ENGINE|none [OUTPUT.ipa]}"
ENGINE="${2:?usage: package-ios.sh APP ENGINE|none [OUTPUT.ipa]}"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/version.json")"
KIND="$([[ "$ENGINE" = none ]] && echo unsigned || echo personal-unsigned)"
OUTPUT="${3:-$ROOT/artifacts/SunPad-v$VERSION-ios-$KIND.ipa}"
MOLTENVK_LICENSE="$ROOT/ref/moltenvk/MoltenVK/LICENSE"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sunpad-package.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "package-ios: $*" >&2; exit 1; }

if [[ "$APP" = *.ipa ]]; then
  ditto -x -k "$APP" "$WORK/published"
  APP="$WORK/published/Payload/SunPad.app"
  [[ ! -e "$APP/Frameworks/libsms_embed.dylib" ]] || fail "the published app already contains an engine"
fi
[[ -d "$APP" ]] || fail "app not found: $APP"
[[ "$ENGINE" = none || -f "$ENGINE" ]] || fail "engine not found: $ENGINE"
[[ -f "$MOLTENVK_LICENSE" ]] || fail "run scripts/fetch-moltenvk.sh first"

STAGED="$WORK/package/Payload/SunPad.app"
mkdir -p "$(dirname "$STAGED")"
ditto "$APP" "$STAGED"
rm -rf "$STAGED/_CodeSignature" "$STAGED/embedded.mobileprovision" "$STAGED/SourceNotices"
rm -f "$STAGED/Frameworks/libsms_embed.dylib"  # a development build's own copy (embed-engine-dev.sh)
if [[ "$ENGINE" != none ]]; then
  mkdir -p "$STAGED/Frameworks"
  ditto "$ENGINE" "$STAGED/Frameworks/libsms_embed.dylib"
  codesign --remove-signature "$STAGED/Frameworks/libsms_embed.dylib" 2>/dev/null || true
fi
codesign --remove-signature "$STAGED" 2>/dev/null || true
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$ROOT/docs/INSTALL_IPA.md" "$STAGED/"
"$ROOT/scripts/package-notices.sh" "$STAGED/SourceNotices"
mkdir -p "$STAGED/SourceNotices/licenses/MoltenVK"
cp "$MOLTENVK_LICENSE" "$STAGED/SourceNotices/licenses/MoltenVK/LICENSE"

# Audit: an arm64 iOS 16 app with MoltenVK and no game code of its own.
EXECUTABLE="$STAGED/SunPad"
xcrun vtool -show-build "$EXECUTABLE" | grep -q 'platform IOS$' || fail "the app is not an iOS device build"
xcrun vtool -show-build "$EXECUTABLE" | grep -q 'minos 16.0' || fail "the app does not target iOS 16"
nm "$EXECUTABLE" | grep -q ' _vkGetInstanceProcAddr$' || fail "the app does not contain MoltenVK"
! nm "$EXECUTABLE" | grep -q -E ' _SMS_main$| _sms_embed_start$' || fail "the app contains game code"
! find "$STAGED" \( -iname '*.iso' -o -iname '*.gcm' -o -iname '*.gci' -o -name 'gGMSE01*' \) | grep -q . ||
  fail "the app contains game data, saves or a translated module"
if [[ "$ENGINE" = none ]]; then
  [[ ! -e "$STAGED/Frameworks/libsms_embed.dylib" ]] || fail "the published app contains an engine"
else
  LIBRARY="$STAGED/Frameworks/libsms_embed.dylib"
  xcrun vtool -show-build "$LIBRARY" | grep -q 'platform IOS$' || fail "the engine is not an iOS device build"
  xcrun vtool -show-build "$LIBRARY" | grep -q 'minos 16.0' || fail "the engine does not target iOS 16"
  [[ -z "$(nm -gU "$LIBRARY" | awk '{print $3}' | grep -v '^_sms_embed_')" ]] || fail "the engine exports more than sms_embed_*"
  [[ -z "$(otool -L "$LIBRARY" | tail -n +2 | awk '{print $1}' | grep -v -E '^(@rpath/libsms_embed.dylib|/usr/lib/libSystem.B.dylib|/usr/lib/libc\+\+.1.dylib|/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation)$')" ]] ||
    fail "the engine links more than libSystem, libc++ and CoreFoundation"
fi

find "$WORK/package" -exec touch -h -t 200001010000 {} +
mkdir -p "$(dirname "$OUTPUT")"
(cd "$WORK/package" && find Payload \( -type f -o -type l \) -print | LC_ALL=C sort | zip -X -q -y "$WORK/SunPad.ipa" -@)
mv "$WORK/SunPad.ipa" "$OUTPUT"
echo "IPA: $OUTPUT"
shasum -a 256 "$OUTPUT"
