#import <Foundation/Foundation.h>

#include <cassert>
#include <iostream>

#import "SunPadControllerRumble.h"

extern "C" bool SunPadSetRumble(bool enabled);

int main(void) {
    @autoreleasepool {
        SunPadControllerRumble *rumble = [SunPadControllerRumble sharedRumble];
        assert(rumble == [SunPadControllerRumble sharedRumble]);

        // Off by default: the runtime falls back to Dolphin's own output path.
        assert(!rumble.allowed);
        assert(!SunPadSetRumble(true));
        assert(!SunPadSetRumble(false));

        // Allowed but no controller with haptics: still not handled.
        rumble.allowed = YES;
        assert(rumble.allowed);
        [rumble useController:nil];
        assert(!SunPadSetRumble(true));
        assert(![rumble setRumbleEnabled:YES]);

        rumble.allowed = NO;
        assert(!rumble.allowed);
        assert(!SunPadSetRumble(true));

        std::cout << "SunPad controller rumble regression test passed\n";
    }
    return 0;
}
