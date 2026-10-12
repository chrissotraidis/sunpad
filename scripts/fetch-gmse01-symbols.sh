#!/usr/bin/env bash
# Fetch the CC0 GMSE01 symbol map, verify it, and write a function map
# ("ADDR SIZE name", the format DolRecomp's --map reads) under the ignored
# game workspace. Overrides exist so the fixture test can run offline.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMMIT=d5f4eb3eb54ac49638b5513efb1fc368068805da
BASE="https://raw.githubusercontent.com/chasem-dev/sms-english/$COMMIT/config/GMSE01"
EXPECT_SHA256=${SYMBOLS_SHA256:-c75a8f35c1d51e7978cc66aeaa86c1d4e2d16c5603576183e0cd49e66a8d98ff}
DOL=${SYMBOLS_DOL:-$ROOT/ref/ModernGekko-Template/extracted/Super-Mario-Sunshine/sys/main.dol}
OUT=${SYMBOLS_OUT:-$ROOT/ref/ModernGekko-Template/build/symbols/GMSE01.map}

[[ -f "$DOL" ]] || { echo "fetch-gmse01-symbols: missing $DOL; run prepare-game.sh first" >&2; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if [[ -n "${SYMBOLS_SOURCE:-}" ]]; then
  cp "$SYMBOLS_SOURCE/symbols.txt" "$SYMBOLS_SOURCE/build.sha1" "$WORK/"
else
  curl -fsSL -o "$WORK/symbols.txt" "$BASE/symbols.txt"
  curl -fsSL -o "$WORK/build.sha1" "$BASE/build.sha1"
fi

actual=$(shasum -a 256 "$WORK/symbols.txt" | awk '{print $1}')
[[ "$actual" == "$EXPECT_SHA256" ]] || {
  echo "fetch-gmse01-symbols: symbols.txt SHA-256 $actual does not match $EXPECT_SHA256" >&2; exit 1; }
expected_dol=$(awk '{print $1; exit}' "$WORK/build.sha1")
actual_dol=$(shasum -a 1 "$DOL" | awk '{print $1}')
[[ "$actual_dol" == "$expected_dol" ]] || {
  echo "fetch-gmse01-symbols: main.dol SHA-1 $actual_dol does not match the map's $expected_dol" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
sed -nE 's/^([^ ]+) = \.[a-z]+:0x([0-9A-Fa-f]{8}); \/\/ type:function size:0x([0-9A-Fa-f]+).*/\2 \3 \1/p' \
  "$WORK/symbols.txt" > "$OUT.tmp"
[[ -s "$OUT.tmp" ]] || { echo "fetch-gmse01-symbols: no functions parsed" >&2; exit 1; }
mv "$OUT.tmp" "$OUT"
echo "wrote $(wc -l < "$OUT" | tr -d ' ') functions to $OUT"
