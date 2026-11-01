#import <Foundation/Foundation.h>

#include "nsogc_protocol.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NSOGCControllerStatus) {
  NSOGCControllerStatusConnecting,
  NSOGCControllerStatusInitializing,
  NSOGCControllerStatusReady,
  NSOGCControllerStatusDisconnected,
};

@class NSOGCController;

typedef void (^NSOGCInputHandler)(NSOGCController *controller, nsogc_state state);

// One NSO GameCube controller. NSOGCManager creates them; an app only reads
// their state or sets an input handler.
@interface NSOGCController : NSObject

// Stable per device on this phone (CoreBluetooth's peripheral identifier).
@property(nonatomic, readonly) NSUUID *identifier;
@property(nonatomic, readonly, copy) NSString *name;
@property(nonatomic, readonly) NSOGCControllerStatus status;

// 0-based player, shown on the controller's LEDs.
@property(nonatomic, readonly) NSInteger playerIndex;

// Connected with a USB cable (macOS) rather than over Bluetooth.
@property(nonatomic, readonly, getter=isWired) BOOL wired;

// Latest input, normalized and as received. Safe to read from any thread.
@property(nonatomic, readonly) nsogc_state state;
@property(nonatomic, readonly) nsogc_raw_input rawInput;

// Starts as nsogc_calibration_default with the stick centres taken from the
// first reports at rest.
@property(nonatomic) nsogc_calibration calibration;

// Called on the manager's callbackQueue with every new report. Reports that
// arrive while an earlier one is still queued replace it, so a busy main
// thread only ever gets the latest state. With the manager's
// deliversInputOnBluetoothQueue, called on the Bluetooth queue for every
// report instead.
@property(nonatomic, copy, nullable) NSOGCInputHandler inputHandler;

- (void)setRumble:(BOOL)on;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
