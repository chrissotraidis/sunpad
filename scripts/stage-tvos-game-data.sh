#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 || "$1" != /* || ! -d "$1" ]]; then
  echo "usage: $0 /absolute/path/to/extracted/GMSE01 <Apple-TV-device>" >&2
  exit 64
fi
SOURCE_ROOT="$1"
DEVICE="$2"
BUNDLE_IDENTIFIER="${SUNPAD_TVOS_BUNDLE_IDENTIFIER:-com.sunpad.SunPad.tv}"
BOOT="$SOURCE_ROOT/sys/boot.bin"
DOL="$SOURCE_ROOT/sys/main.dol"
for required in "$BOOT" "$SOURCE_ROOT/sys/bi2.bin" \
  "$SOURCE_ROOT/sys/apploader.img" "$SOURCE_ROOT/sys/fst.bin" "$DOL" \
  "$SOURCE_ROOT/files/opening.bnr" "$SOURCE_ROOT/files/AudioRes/mSound.asn" \
  "$SOURCE_ROOT/files/data/common.szs"; do
  [[ -f "$required" ]] || { echo "incomplete GMSE01 data: $required" >&2; exit 66; }
done
[[ "$(dd if="$BOOT" bs=1 count=6 2>/dev/null)" = GMSE01 ]] || exit 65
[[ "$(xxd -p -s 6 -l 2 "$BOOT")" = 0000 ]] || exit 65
[[ "$(xxd -p -s 28 -l 4 "$BOOT")" = c2339f3d ]] || exit 65
[[ "$(shasum -a 256 "$DOL" | awk '{print $1}')" = \
  13934c863d649b1ddca1ca4d7748f49d28a571685cbee5fb1542545c32869955 ]] || {
  echo "sys/main.dol does not match GMSE01 USA revision 0" >&2
  exit 65
}
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/sunpad-tvos-stage.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/SunPad/GameData"
cp -cR "$SOURCE_ROOT" "$STAGING/SunPad/GameData/GMSE01"
xcrun devicectl device copy to --device "$DEVICE" --source "$STAGING" \
  --destination "Library/Caches" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_IDENTIFIER" \
  --remove-existing-content false
echo "Staged validated GMSE01 data for SunPad on $DEVICE."
