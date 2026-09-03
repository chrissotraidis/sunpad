#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/sunpad-tvos-controller-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

cat >"$test_root/SunPadTVControllerTests.mm" <<'EOF'
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

#include <cassert>
#include <iostream>

#import "SunPadTVControllerManager.h"

int main() {
    @autoreleasepool {
        SunPadControllerButtonMapping mapping =
            SunPadDefaultControllerButtonMapping();
        assert(SunPadTVInputStateFromExtendedGamepad(nil, mapping).connected == 0);

        GCController *controller = [GCController controllerWithExtendedGamepad];
        GCExtendedGamepad *gamepad = controller.extendedGamepad;
        assert(gamepad != nil);
        [gamepad.buttonA setValue:1.0f];
        [gamepad.buttonB setValue:1.0f];
        [gamepad.buttonX setValue:1.0f];
        [gamepad.buttonY setValue:1.0f];
        [gamepad.leftShoulder setValue:1.0f];
        [gamepad.rightShoulder setValue:1.0f];
        [gamepad.buttonMenu setValue:1.0f];
        [gamepad.dpad setValueForXAxis:-1.0f yAxis:1.0f];
        [gamepad.leftThumbstick setValueForXAxis:0.5f yAxis:-1.0f];
        [gamepad.rightThumbstick setValueForXAxis:-0.25f yAxis:0.75f];
        [gamepad.leftTrigger setValue:0.5f];
        [gamepad.rightTrigger setValue:0.25f];

        SunPadInputState state =
            SunPadTVInputStateFromExtendedGamepad(gamepad, mapping);
        assert(state.connected == 1);
        assert((state.buttons & (SunPadButtonA | SunPadButtonB |
                                 SunPadButtonX | SunPadButtonY |
                                 SunPadButtonZ | SunPadButtonStart |
                                 SunPadButtonDpadLeft | SunPadButtonDpadUp |
                                 SunPadButtonL | SunPadButtonR)) ==
               (SunPadButtonA | SunPadButtonB | SunPadButtonX |
                SunPadButtonY | SunPadButtonZ | SunPadButtonStart |
                SunPadButtonDpadLeft | SunPadButtonDpadUp |
                SunPadButtonL | SunPadButtonR));
        assert(state.stickX == 64 && state.stickY == -127);
        assert(state.cStickX == -32 && state.cStickY == 95);
        assert(state.triggerL == 128 && state.triggerR == 128);

        [gamepad.buttonA setValue:0.0f];
        [gamepad.buttonB setValue:0.0f];
        [gamepad.buttonX setValue:0.0f];
        [gamepad.buttonY setValue:0.0f];
        [gamepad.leftShoulder setValue:0.0f];
        [gamepad.rightShoulder setValue:0.0f];
        [gamepad.buttonMenu setValue:0.0f];
        [gamepad.dpad setValueForXAxis:0.0f yAxis:0.0f];
        [gamepad.leftThumbstick setValueForXAxis:0.0f yAxis:0.0f];
        [gamepad.rightThumbstick setValueForXAxis:0.0f yAxis:0.0f];
        [gamepad.leftTrigger setValue:0.0f];
        [gamepad.rightTrigger setValue:0.0f];
        state = SunPadTVInputStateFromExtendedGamepad(gamepad, mapping);
        assert(state.connected == 1 && state.buttons == 0);
        assert(state.stickX == 0 && state.stickY == 0 &&
               state.cStickX == 0 && state.cStickY == 0);
        assert(state.triggerL == 0 && state.triggerR == 0);

        std::cout << "SunPad tvOS controller conversion test passed\n";
    }
    return 0;
}
EOF

xcrun clang++ -std=c++20 -fobjc-arc \
  -framework Foundation -framework GameController \
  -I"$repo_root/apple/tvos" \
  -I"$repo_root/apple/shared" \
  "$test_root/SunPadTVControllerTests.mm" \
  "$repo_root/apple/tvos/SunPadTVControllerManager.mm" \
  "$repo_root/apple/shared/SunPadControllerMapping.mm" \
  -o "$test_root/SunPadTVControllerTests"
"$test_root/SunPadTVControllerTests"
