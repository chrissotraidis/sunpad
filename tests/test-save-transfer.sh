#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

clang++ -x objective-c++ -std=gnu++2b -fobjc-arc \
  -framework Foundation \
  -I"$ROOT/apple/shared" \
  "$ROOT/apple/shared/SunPadSaveTransfer.mm" \
  "$ROOT/tests/SunPadSaveTransferTests.mm" \
  -o "$TEMP_DIR/SunPadSaveTransferTests"

"$TEMP_DIR/SunPadSaveTransferTests"
