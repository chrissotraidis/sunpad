#import "SunPadEngineBridge.h"

#include <cassert>
#include <cstring>

static NSDictionary<NSString *, NSString *> *Environment(SunPadEngineChoices choices) {
    return SunPadEngineEnvironment(choices, @"/engine", @"/caches");
}

int main() {
    @autoreleasepool {
        SunPadEngineChoices choices = {1, SunPadAspectRatioOriginal, NO, YES};
        NSDictionary *environment = Environment(choices);
        assert([environment[@"SMS_GX_SCALE"] isEqualToString:@"1"]);
        assert([environment[@"SMS_WIDESCREEN"] isEqualToString:@"0"]);
        assert([environment[@"SMS_ASPECT"] isEqualToString:@"keep"]);
        assert([environment[@"SMS_FRAME_RATE"] isEqualToString:@"30"]);
        assert([environment[@"SMS_HEAT_HAZE"] isEqualToString:@"1"]);
        assert([environment[@"SMS_RUMBLE"] isEqualToString:@"1"]);
        assert([environment[@"SMS_SAVE_DIR"] isEqualToString:@"/engine/card-a"]);
        assert([environment[@"SMS_SETTINGS"] isEqualToString:@"/engine/settings.txt"]);
        assert([environment[@"XDG_CACHE_HOME"] isEqualToString:@"/caches"]);
        assert([environment[@"SMS_RETAIL_UI"] isEqualToString:@"1"]);
        assert([environment[@"SMS_PAUSE_TRACKER"] isEqualToString:@"0"]);
        assert([environment[@"SMS_RADAR"] isEqualToString:@"0"]);
        assert([environment[@"SMS_COOP"] isEqualToString:@"0"]);
        assert([environment[@"SMS_GX_HITCH_MS"] isEqualToString:@"50"]);
        assert([environment[@"SMS_GX_STATS"] isEqualToString:@"300"]);
        assert([environment[@"SMS_VK_ASYNC_PIPELINES"] isEqualToString:@"1"]);

        choices.renderScale = 9;
        choices.aspectRatio = SunPadAspectRatioWidescreen;
        choices.sixtyFPS = YES;
        choices.rumble = NO;
        environment = Environment(choices);
        assert([environment[@"SMS_GX_SCALE"] isEqualToString:@"4"]);
        assert([environment[@"SMS_WIDESCREEN"] isEqualToString:@"16:9"]);
        assert([environment[@"SMS_ASPECT"] isEqualToString:@"keep"]);
        assert([environment[@"SMS_FRAME_RATE"] isEqualToString:@"60"]);
        assert([environment[@"SMS_HEAT_HAZE"] isEqualToString:@"0"]);
        assert([environment[@"SMS_RUMBLE"] isEqualToString:@"0"]);

        choices.renderScale = 0;
        choices.aspectRatio = SunPadAspectRatioFillScreen;
        environment = Environment(choices);
        assert([environment[@"SMS_GX_SCALE"] isEqualToString:@"1"]);
        assert([environment[@"SMS_WIDESCREEN"] isEqualToString:@"16:9"]);
        assert([environment[@"SMS_ASPECT"] isEqualToString:@"stretch"]);
        assert([environment[@"SMS_HEAT_HAZE"] isEqualToString:@"0"]);

        SunPadInputState input = {};
        input.stickX = 127;
        input.stickY = -127;
        input.cStickX = 64;
        input.cStickY = -127;
        input.triggerL = 26;
        input.triggerR = 255;
        input.buttons = SunPadButtonA | SunPadButtonStart | SunPadButtonR | SunPadButtonDpadLeft;
        SmsEmbedPad pad = SunPadEnginePad(input, NO, NO);
        assert(pad.connected == 1);
        assert(pad.stickX == 100 && pad.stickY == -100);
        assert(pad.substickX == 50 && pad.substickY == -100);
        assert(pad.triggerL == 26 && pad.triggerR == 255);
        // SunPad's button bits are the GameCube's PAD bits (dolphin/pad.h).
        assert(pad.buttons == (0x0100 | 0x1000 | 0x0020 | 0x0001));

        pad = SunPadEnginePad(input, YES, YES);
        assert(pad.substickX == -50 && pad.substickY == 100);
        assert(pad.stickX == 100 && pad.stickY == -100);
    }
    return 0;
}
