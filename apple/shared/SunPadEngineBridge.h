#pragma once

#import <Foundation/Foundation.h>

#include "SunPadInputState.h"
#import "SunPadSettings.h"
#include "embed/sms_embed.h"

NS_ASSUME_NONNULL_BEGIN

/* SunPad's settings and input in the decompilation engine's terms
 * (docs/DECOMP-ENGINE-PLAN.md, "SunPad controls and settings"). */

typedef struct {
    NSInteger renderScale;               // 1..4
    SunPadAspectRatioMode aspectRatio;   // as SunPadSettings
    BOOL sixtyFPS;                       // the experimental 60 FPS choice
    BOOL rumble;                         // Controls > Controller Rumble
} SunPadEngineChoices;

/* The engine's SMS_* environment variables for these choices. Save, settings
 * and cache files live under engineDirectory and cacheDirectory. */
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *SunPadEngineEnvironment(
    SunPadEngineChoices choices, NSString *engineDirectory, NSString *cacheDirectory);

/* Player one's controller: sticks from SunPad's -127..127 to the engine's
 * -100..100, the camera options applied, buttons as GameCube PAD bits (SunPad
 * uses the same bits). */
FOUNDATION_EXPORT SmsEmbedPad SunPadEnginePad(
    SunPadInputState input, BOOL modernCStickHorizontal, BOOL invertCStickVertical);

NS_ASSUME_NONNULL_END
