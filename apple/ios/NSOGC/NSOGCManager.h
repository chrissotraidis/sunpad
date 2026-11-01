#import <Foundation/Foundation.h>

#import "NSOGCController.h"

NS_ASSUME_NONNULL_BEGIN

@class NSOGCManager;

@protocol NSOGCManagerDelegate <NSObject>
@optional
// The controller finished its setup and is sending input.
- (void)manager:(NSOGCManager *)manager didConnectController:(NSOGCController *)controller
    NS_SWIFT_NAME(manager(_:didConnect:));
- (void)manager:(NSOGCManager *)manager didDisconnectController:(NSOGCController *)controller
    NS_SWIFT_NAME(manager(_:didDisconnect:));
- (void)manager:(NSOGCManager *)manager bluetoothAvailabilityDidChange:(BOOL)available
    NS_SWIFT_NAME(manager(_:bluetoothAvailabilityDidChange:));
@end

// Finds, connects and sets up NSO GameCube controllers over CoreBluetooth,
// and on macOS over USB too.
//
// Over Bluetooth a controller is found while it advertises: after its SYNC
// button is pressed (about 60 seconds), or when it wakes and looks for its
// last host. Once set up, the manager remembers it and connects again on its
// own whenever it is in range. The app needs NSBluetoothAlwaysUsageDescription
// in its Info.plist. Over USB (macOS) a controller is set up as soon as it is
// plugged in; iOS gives apps no access to USB devices.
@interface NSOGCManager : NSObject

@property(class, nonatomic, readonly) NSOGCManager *sharedManager NS_SWIFT_NAME(shared);

@property(nonatomic, weak, nullable) id<NSOGCManagerDelegate> delegate;

// Where delegate calls, input handlers and log lines are delivered. Main by
// default. Set it before start.
@property(nonatomic, strong) dispatch_queue_t callbackQueue;

// Receives one line per event (discovery, setup steps, errors), on the
// callbackQueue.
@property(nonatomic, copy, nullable) void (^logHandler)(NSString *line);

// Controllers that are set up and sending input, in player order.
@property(nonatomic, readonly) NSArray<NSOGCController *> *controllers;

// How many controllers to connect before scanning stops. 4 by default.
@property(nonatomic) NSUInteger maximumControllers;

// Which transports start uses. Both YES by default; USB is macOS only. Set
// them before start.
@property(nonatomic) BOOL usesBluetooth;
@property(nonatomic) BOOL usesUSB;

// When YES, input handlers run on the Bluetooth queue as each report arrives,
// with no hop to callbackQueue: the lowest latency, for handlers that are fast
// and thread-safe (a game's input state behind a lock, say). NO by default.
// Set it before start.
@property(nonatomic) BOOL deliversInputOnBluetoothQueue;

@property(nonatomic, readonly, getter=isRunning) BOOL running;

// Looking for a controller in SYNC mode: running, and fewer controllers than
// maximumControllers are connected.
@property(nonatomic, readonly, getter=isScanning) BOOL scanning;

// A controller was set up before and will be reconnected when it is in range.
@property(nonatomic, readonly) BOOL hasRememberedControllers;

// Turns Bluetooth on for the app (the first call shows the permission prompt),
// reconnects remembered controllers and scans for new ones.
- (void)start;

// Stops scanning and disconnects every controller.
- (void)stop;

// Forgets remembered controllers. Connected ones stay connected.
- (void)forgetControllers;

// Disconnects one controller. A remembered one is reconnected when it comes
// back, unless it was forgotten first.
- (void)disconnectController:(NSOGCController *)controller NS_SWIFT_NAME(disconnect(_:));

@end

NS_ASSUME_NONNULL_END
