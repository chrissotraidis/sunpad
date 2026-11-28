#!/usr/bin/env bash
# Packages SunPad for iPhone and iPad.
# usage: package-ios.sh APP ENGINE|none [OUTPUT.ipa]
#   APP     a built SunPad.app, or the published SunPad IPA
#   ENGINE  the player's libsms_embed.dylib, or "none" for the published app,
#           which carries no game code
# Both are audited (audit-ios-package.sh); the IPA is unsigned and must be
# signed before installing.
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

find "$WORK/package" -exec touch -h -t 200001010000 {} +
mkdir -p "$(dirname "$OUTPUT")"
(cd "$WORK/package" && find Payload \( -type f -o -type l \) -print | LC_ALL=C sort | zip -X -q -y "$WORK/SunPad.ipa" -@)
mv "$WORK/SunPad.ipa" "$OUTPUT"
if [[ "$ENGINE" = none ]]; then
  SUNPAD_APP_ONLY=1 "$ROOT/scripts/audit-ios-package.sh" "$OUTPUT"
else
  "$ROOT/scripts/audit-ios-package.sh" "$OUTPUT"
fi
echo "IPA: $OUTPUT"
shasum -a 256 "$OUTPUT"
