#import "SunPadEngineBridge.h"

#include <algorithm>

NSDictionary<NSString *, NSString *> *SunPadEngineEnvironment(
    SunPadEngineChoices choices, NSString *engineDirectory, NSString *cacheDirectory) {
    const NSInteger scale = std::max<NSInteger>(1, std::min<NSInteger>(4, choices.renderScale));
    // As SunPad's Dolphin engine shows them: 16:9 widens the game's camera, and
    // Fill Screen stretches that 16:9 picture to the screen. Both leave out the
    // heat-wave shimmer, as SunPad's wide modes always have.
    NSString *widescreen = choices.aspectRatio == SunPadAspectRatioOriginal ? @"0" : @"16:9";
    NSString *aspect = choices.aspectRatio == SunPadAspectRatioFillScreen ? @"stretch" : @"keep";
    NSString *heatHaze = choices.aspectRatio == SunPadAspectRatioOriginal ? @"1" : @"0";
    return @{
        @"SMS_GX_SCALE": [NSString stringWithFormat:@"%ld", (long)scale],
        @"SMS_WIDESCREEN": widescreen,
        @"SMS_ASPECT": aspect,
        @"SMS_HEAT_HAZE": heatHaze,
        @"SMS_FRAME_RATE": choices.sixtyFPS ? @"60" : @"30",
        @"SMS_RUMBLE": choices.rumble ? @"1" : @"0",
        @"SMS_SAVE_DIR": [engineDirectory stringByAppendingPathComponent:@"card-a"],
        @"SMS_SETTINGS": [engineDirectory stringByAppendingPathComponent:@"settings.txt"],
        @"XDG_CACHE_HOME": cacheDirectory,
        @"SMS_TEXTURE_PACKS": @"0",
        @"SMS_NO_GC_ADAPTER": @"1",
        @"SMS_PRESENCE": @"0",
        @"SMS_QUIET_STUBS": @"1",
        // The game as SunPad has always shown it: SunPad's menu holds the settings,
        // so the PC port's own additions to the pause menu, the movies and the HUD,
        // and its split-screen co-op, stay out.
        @"SMS_RETAIL_UI": @"1",
        @"SMS_PAUSE_TRACKER": @"0",
        @"SMS_RADAR": @"0",
        @"SMS_COOP": @"0",
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
