#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SunPadNSOGCStatus) {
    SunPadNSOGCStatusOff,          // turned off from the Controls menu
    SunPadNSOGCStatusUnavailable,  // Bluetooth is off or not allowed for SunPad
    SunPadNSOGCStatusSearching,    // waiting for the remembered controller or one in SYNC mode
    SunPadNSOGCStatusConnected,
};

/* Connects a Nintendo Switch Online GameCube controller made for the Switch 2,
 * which iOS has no driver for, over Bluetooth LE through NSOGCKit (NSOGC/).
 * Its input is player one's, like a GameController pad's, and it takes player
 * one's rumble. Main thread only, except where noted. */
@interface SunPadNSOGCBridge : NSObject

+ (instancetype)sharedBridge;

/* Starts Bluetooth unless the controller was turned off from the Controls
 * menu. The first start shows the Bluetooth permission prompt. It also takes
 * the controller back if an app that embeds SunPad among other games used it
 * meanwhile. */
- (void)start;

/* Turns the controller on: reconnects the remembered one and looks for one in
 * SYNC mode. The choice is kept across launches. */
- (void)connect;

/* Disconnects and stays off until connect. */
- (void)disconnect;

/* Forgets the remembered controller and disconnects it; a controller in SYNC
 * mode can then pair. */
- (void)forgetController;

@property(nonatomic, readonly) SunPadNSOGCStatus status;
@property(nonatomic, readonly) BOOL controllerConnected;
@property(nonatomic, readonly, nullable) NSString *controllerName;
@property(nonatomic, readonly) BOOL hasRememberedController;

/* Called when the controller connects or disconnects, or is turned on or
 * off. */
@property(nonatomic, copy, nullable) void (^connectionChangedHandler)(void);

/* Called on the Bluetooth queue right after each report reached the input
 * mixer, so the game can be fed without waiting for the next tick. Set it
 * before start. */
@property(nonatomic, copy, nullable) void (^inputUpdatedHandler)(void);

/* Called when the controller's HOME button is pressed. An app that embeds
 * SunPad can use it to bring back its own menu; SunPad leaves it unset. */
@property(nonatomic, copy, nullable) void (^homeButtonHandler)(void);

@end

NS_ASSUME_NONNULL_END
