#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_binary="$(mktemp "${TMPDIR:-/tmp}/sunpad-engine-bridge.XXXXXX")"
trap 'rm -f "$test_binary"' EXIT

[[ -f "$repo_root/ref/sms-pc-port/platform/embed/sms_embed.h" ]] || {
  echo "Run bootstrap-dependencies.sh --sources-only first" >&2
  exit 1
}
clang++ -std=c++17 -fobjc-arc \
  -I "$repo_root/apple/shared" -I "$repo_root/ref/sms-pc-port/platform" \
  "$repo_root/apple/shared/SunPadEngineBridge.mm" \
  "$repo_root/apple/shared/SunPadSettings.mm" \
  "$repo_root/tests/SunPadEngineBridgeTests.mm" \
  -framework Foundation -framework CoreGraphics -o "$test_binary"
"$test_binary"
echo "Engine settings and input bridge tests passed"
