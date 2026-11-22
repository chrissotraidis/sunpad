#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_binary="$(mktemp "${TMPDIR:-/tmp}/sunpad-engine-saves.XXXXXX")"
trap 'rm -f "$test_binary"' EXIT

clang++ -std=c++17 -fobjc-arc -I "$repo_root/apple/shared" \
  "$repo_root/apple/shared/SunPadEngineSaves.mm" \
  "$repo_root/apple/shared/SunPadSaveTransfer.mm" \
  "$repo_root/tests/SunPadEngineSavesTests.mm" \
  -framework Foundation -o "$test_binary"
"$test_binary"
echo "Engine save migration and GCI round-trip tests passed"
