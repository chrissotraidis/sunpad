#pragma once

#import <Foundation/Foundation.h>

@class GCController;

NS_ASSUME_NONNULL_BEGIN

/* Plays the game's rumble on player one's controller through Core Haptics.
 * The runtime reaches it through SunPadSetRumble, which RecompCore's
 * Pad::Rumble calls for pad 0 on iOS and iPadOS. */
@interface SunPadControllerRumble : NSObject

+ (instancetype)sharedRumble;

/* Whether the player turned rumble on. Off stops any rumble at once. */
@property(atomic, assign) BOOL allowed;

/* Follows player one's controller, or none when nil. Call on the main thread
 * whenever controllers are reconciled; it restarts haptics that iOS stopped. */
- (void)useController:(nullable GCController *)controller;

/* Starts or stops rumble from any thread. Returns NO when the controller has
 * no haptics or the player turned rumble off. */
- (BOOL)setRumbleEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
