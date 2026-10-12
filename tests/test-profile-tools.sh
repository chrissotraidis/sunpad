#!/usr/bin/env bash
# Fixture checks for fetch-gmse01-symbols.sh and symbolize-profile.py.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FIX="$ROOT/tests/fixtures/profile"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "test-profile-tools: $1" >&2; exit 1; }

SHA=$(shasum -a 256 "$FIX/symbols.txt" | awk '{print $1}')
run_fetch() {
  SYMBOLS_SOURCE="$FIX" SYMBOLS_DOL="$1" SYMBOLS_SHA256="$2" SYMBOLS_OUT="$TMP/GMSE01.map" \
    "$ROOT/scripts/fetch-gmse01-symbols.sh" >/dev/null 2>&1
}

run_fetch "$FIX/main.dol" "$SHA" || fail 'valid fixture was refused'
[[ "$(wc -l < "$TMP/GMSE01.map" | tr -d ' ')" == 3 ]] || fail 'expected three functions'
grep -qx '80348700 200 idleWait__6FakeOSFv' "$TMP/GMSE01.map" || fail 'map line format'
grep -q fixtureTable "$TMP/GMSE01.map" && fail 'objects must be excluded'

rm "$TMP/GMSE01.map"
run_fetch "$FIX/main.dol" 0000 && fail 'mismatched symbols hash was accepted'
printf 'other dol\n' > "$TMP/other.dol"
run_fetch "$TMP/other.dol" "$SHA" && fail 'mismatched main.dol was accepted'
[[ ! -e "$TMP/GMSE01.map" ]] || fail 'refused input still wrote a map'

run_fetch "$FIX/main.dol" "$SHA"
out=$(python3 "$ROOT/scripts/symbolize-profile.py" "$FIX/sample.txt" --map "$TMP/GMSE01.map")
grep -q 'CPU-GPU thread: 100 samples' <<<"$out" || fail 'thread total'
grep -q '40.00%  loop_80348814 (idleWait__6FakeOSFv+0x114)' <<<"$out" || fail 'loop naming'
grep -q 'func_80361600 \[80361600-80365600: drawThing__5FakeGXFv\]' <<<"$out" || fail 'chunk naming'
grep -q '40.00%  StaticRecompCore::Run()' <<<"$out" || fail 'self time'
out=$(python3 "$ROOT/scripts/symbolize-profile.py" "$FIX/sample.txt" --callers __psynch_cvwait)
grep -q '5.00%  AbstractStagingTexture::ReadTexels < chassis_dispatch' <<<"$out" || fail 'callers'
echo 'profile tools: ok'
