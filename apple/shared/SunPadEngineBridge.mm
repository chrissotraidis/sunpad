#import "SunPadEngineBridge.h"

#include <algorithm>

NSDictionary<NSString *, NSString *> *SunPadEngineEnvironment(
    SunPadEngineChoices choices, NSString *engineDirectory, NSString *cacheDirectory) {
    const NSInteger scale = std::max<NSInteger>(1, std::min<NSInteger>(4, choices.renderScale));
    NSString *widescreen = @"0";
    NSString *aspect = @"keep";
    if (choices.aspectRatio == SunPadAspectRatioWidescreen) {
        widescreen = @"16:9";
    } else if (choices.aspectRatio == SunPadAspectRatioFillScreen && choices.drawableSize.width > 0 &&
               choices.drawableSize.height > 0) {
        // The game's camera widened to the screen's own shape, with nothing stretched.
        widescreen = [NSString stringWithFormat:@"%.0f:%.0f", choices.drawableSize.width,
                                                choices.drawableSize.height];
    }
    return @{
        @"SMS_GX_SCALE": [NSString stringWithFormat:@"%ld", (long)scale],
        @"SMS_WIDESCREEN": widescreen,
        @"SMS_ASPECT": aspect,
        @"SMS_FRAME_RATE": choices.sixtyFPS ? @"60" : @"30",
        @"SMS_RUMBLE": choices.rumble ? @"1" : @"0",
        @"SMS_SAVE_DIR": [engineDirectory stringByAppendingPathComponent:@"card-a"],
        @"SMS_SETTINGS": [engineDirectory stringByAppendingPathComponent:@"settings.txt"],
        @"XDG_CACHE_HOME": cacheDirectory,
        @"SMS_TEXTURE_PACKS": @"0",
        @"SMS_NO_GC_ADAPTER": @"1",
        @"SMS_PRESENCE": @"0",
        @"SMS_QUIET_STUBS": @"1",
    };
}

static int8_t EngineAxis(int value) {
    return int8_t(std::max(-100, std::min(100, value * 100 / 127)));
}

SmsEmbedPad SunPadEnginePad(SunPadInputState input, BOOL modernCStickHorizontal, BOOL invertCStickVertical) {
    SmsEmbedPad pad = {};
    pad.connected = 1;
    pad.buttons = input.buttons;
    pad.stickX = EngineAxis(input.stickX);
    pad.stickY = EngineAxis(input.stickY);
    pad.substickX = EngineAxis(modernCStickHorizontal ? -input.cStickX : input.cStickX);
    pad.substickY = EngineAxis(invertCStickVertical ? -input.cStickY : input.cStickY);
    pad.triggerL = input.triggerL;
    pad.triggerR = input.triggerR;
    return pad;
}
