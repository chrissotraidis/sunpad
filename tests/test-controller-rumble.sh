#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/home"

clang++ -x objective-c++ -std=gnu++2b -fobjc-arc \
  -framework Foundation -framework CoreHaptics -framework GameController \
  -I"$ROOT/apple/shared" \
  "$ROOT/apple/shared/SunPadDiagnostics.mm" \
  "$ROOT/apple/shared/SunPadControllerRumble.mm" \
  "$ROOT/tests/SunPadControllerRumbleTests.mm" \
  -o "$TEMP_DIR/SunPadControllerRumbleTests"

CFFIXED_USER_HOME="$TEMP_DIR/home" "$TEMP_DIR/SunPadControllerRumbleTests"

# The haptics engine must be running before a pattern player is created.
rumble="$ROOT/apple/shared/SunPadControllerRumble.mm"
python3 - "$rumble" <<'PY'
import sys
source = open(sys.argv[1]).read()
assert source.index("startAndReturnError") < source.index("createPlayerWithPattern")
PY

grep -Fq 'extern "C" bool SunPadSetRumble(bool enabled)' "$rumble"
grep -Fq 'useController:playerOne' "$ROOT/apple/ios/SunPadGameViewController.mm"
echo "SunPad controller rumble wiring checks passed"
