#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sunpad-controller-slots.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT

clang++ -std=c++23 "$root/tests/SunPadControllerSlotsTests.cpp" \
  -o "$temp_dir/SunPadControllerSlotsTests"
"$temp_dir/SunPadControllerSlotsTests"

clang++ -std=c++23 "$root/tests/SunPadTouchControlsVisibilityTests.cpp" \
  -o "$temp_dir/SunPadTouchControlsVisibilityTests"
"$temp_dir/SunPadTouchControlsVisibilityTests"

clang++ -x objective-c++ -std=gnu++2b -fobjc-arc \
  -framework Foundation \
  -I"$root/apple/shared" \
  "$root/apple/shared/SunPadInputMixer.mm" \
  "$root/tests/SunPadControllerDisconnectTests.mm" \
  -o "$temp_dir/SunPadControllerDisconnectTests"
"$temp_dir/SunPadControllerDisconnectTests"

controller="$root/apple/ios/SunPadGameViewController.mm"
grep -Fq 'GCController.controllers' "$controller"
grep -Fq 'indexOfObjectIdenticalTo:controller' "$controller"
grep -Fq 'reconcileControllersForReason:@"foreground"' "$controller"
grep -Fq 'reconcileControllersForReason:@"periodic"' "$controller"
grep -Fq 'controller.playerIndex = SunPadPlayerIndexForSlot(slot);' "$controller"
grep -Fq 'clearInputFromTouch:NO' "$controller"
grep -Fq '[_overlay refreshControllerVisibility]' "$controller"
grep -Fq 'controller reconciled reason=%@ instance=%@ slot=%ld status=%@' "$controller"

echo "Controller reconciliation source checks passed"
