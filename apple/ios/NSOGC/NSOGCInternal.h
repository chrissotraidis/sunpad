// Interfaces shared by NSOGCManager and NSOGCController only.

#import <CoreBluetooth/CoreBluetooth.h>

#if TARGET_OS_OSX
#import <IOKit/hid/IOHIDManager.h>
#endif

#import "NSOGCController.h"
#import "NSOGCManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSOGCManager ()
// Both run on the manager's Bluetooth queue.
- (void)controllerDidBecomeReady:(NSOGCController *)controller;
- (void)controllerDidFail:(NSOGCController *)controller reason:(NSString *)reason;
- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
@end

@interface NSOGCController () <CBPeripheralDelegate>
// nil for a wired controller.
@property(nonatomic, readonly, nullable) CBPeripheral *peripheral;

// Everything below runs on `queue`, the manager's queue (Bluetooth and USB).
- (instancetype)initWithPeripheral:(CBPeripheral *)peripheral
                           manager:(NSOGCManager *)manager
                             queue:(dispatch_queue_t)queue
                     callbackQueue:(dispatch_queue_t)callbackQueue NS_DESIGNATED_INITIALIZER;
- (void)didConnect;
- (void)didDisconnect;
- (void)assignPlayerIndex:(NSInteger)playerIndex;

#if TARGET_OS_OSX
- (instancetype)initWithHIDDevice:(IOHIDDeviceRef)device
                          manager:(NSOGCManager *)manager
                            queue:(dispatch_queue_t)queue
                    callbackQueue:(dispatch_queue_t)callbackQueue NS_DESIGNATED_INITIALIZER;
@property(nonatomic, readonly) IOHIDDeviceRef hidDevice;
- (void)startWired;
- (void)handleUSBReport:(const uint8_t *)report length:(NSUInteger)length;
#endif
@end

NS_ASSUME_NONNULL_END
