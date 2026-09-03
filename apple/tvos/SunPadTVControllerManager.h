#pragma once

#import <GameController/GameController.h>
#import <Foundation/Foundation.h>

#include "SunPadControllerMapping.h"
#include "SunPadInputState.h"

NS_ASSUME_NONNULL_BEGIN

@class SunPadCoreHost;

/* Converts one Apple extended-gamepad snapshot to the canonical GameCube
 * state. The mapping is an argument so the conversion remains deterministic
 * and independently assertable. */
FOUNDATION_EXPORT SunPadInputState SunPadTVInputStateFromExtendedGamepad(
    GCExtendedGamepad *_Nullable gamepad,
    SunPadControllerButtonMapping mapping);

@interface SunPadTVControllerManager : NSObject

- (instancetype)initWithHost:(SunPadCoreHost *)host NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)activate;
- (void)deactivate;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
