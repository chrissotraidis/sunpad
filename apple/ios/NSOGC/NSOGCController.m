#import "NSOGCInternal.h"

#import <math.h>
#import <os/lock.h>

#if TARGET_OS_OSX
#import <IOUSBHost/IOUSBHost.h>
#endif

// Writing 01 00 to the control service's write characteristic turns the
// controller's protocol on. The Nintendo service carries the command channel.
static NSString *const kControlServiceUUID = @"00C5AF5D-1964-4E30-8F51-1956F96BD280";
static NSString *const kNintendoServiceUUID = @"AB7DE9BE-89FE-49AD-828F-118F09DF7FD0";

// The Nintendo service has two input report characteristics. This one
// carries the GameCube layout nsogc_parse_report decodes; the other starts in
// another layout and stops once the default report command is sent.
static NSString *const kNativeInputUUID = @"8261CBA1-9435-420C-84D6-F0C75A2C8E4D";

// iOS may answer the first writes with an authentication error while it
// pairs with the controller (and shows the pairing alert), so writes and
// subscriptions are retried for a while before setup gives up.
static const NSInteger kMaxAttempts = 10;
static const int64_t kRetryDelay = 2 * NSEC_PER_SEC;
static const int64_t kSetupTimeout = 45 * NSEC_PER_SEC;
static const int64_t kKeepAliveInterval = 1 * NSEC_PER_SEC;
static const NSUInteger kMaxQueuedCommands = 16;

// Stick centres come from the first reports, if the sticks are at rest then.
static const NSUInteger kCenterSamples = 8;
static const float kCenterTolerance = 200.0f;
static const CFTimeInterval kSummaryInterval = 10.0;

typedef NS_ENUM(NSInteger, NSOGCSetupStep) {
  NSOGCSetupStepIdle,
  NSOGCSetupStepDiscovering,
  NSOGCSetupStepEnabling,
  NSOGCSetupStepSubscribing,
  NSOGCSetupStepConfiguring,
  NSOGCSetupStepReady,
};

static NSString *NSOGCHex(NSData *data, NSUInteger limit) {
  const uint8_t *bytes = data.bytes;
  NSUInteger count = MIN(data.length, limit);
  NSMutableString *text = [NSMutableString stringWithCapacity:count * 3 + 2];
  for (NSUInteger i = 0; i < count; i++)
    [text appendFormat:i == 0 ? @"%02X" : @" %02X", bytes[i]];
  if (data.length > limit)
    [text appendString:@" …"];
  return text;
}

static NSString *NSOGCPropertyNames(CBCharacteristicProperties properties) {
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  if (properties & CBCharacteristicPropertyRead) [names addObject:@"read"];
  if (properties & CBCharacteristicPropertyWrite) [names addObject:@"write"];
  if (properties & CBCharacteristicPropertyWriteWithoutResponse) [names addObject:@"write-no-response"];
  if (properties & CBCharacteristicPropertyNotify) [names addObject:@"notify"];
  if (properties & CBCharacteristicPropertyIndicate) [names addObject:@"indicate"];
  return names.count ? [names componentsJoinedByString:@","] : @"none";
}

static NSString *NSOGCFormatName(nsogc_report_format format) {
  switch (format) {
    case NSOGC_REPORT_NATIVE: return @"native";
    case NSOGC_REPORT_PRO_FULL: return @"pro 0x30";
    case NSOGC_REPORT_PRO_SHORT: return @"pro short";
    default: return @"invalid";
  }
}

@implementation NSOGCController {
  __weak NSOGCManager *_manager;
  dispatch_queue_t _queue;
  dispatch_queue_t _callbackQueue;

  // Guards what other threads read.
  os_unfair_lock _lock;
  NSOGCControllerStatus _status;
  NSInteger _playerIndex;
  nsogc_state _state;
  nsogc_raw_input _raw;
  nsogc_calibration _calibration;
  NSOGCInputHandler _inputHandler;
  BOOL _deliveryPending;
  NSUInteger _centerCount;
  double _centerSum[4];

  // Bluetooth queue only.
  NSOGCSetupStep _step;
  NSUInteger _pendingDiscoveries;
  CBCharacteristic *_controlCharacteristic;
  CBCharacteristic *_commandCharacteristic;
  CBCharacteristic *_inputCharacteristic;
  CBCharacteristic *_nativeInputCharacteristic;
  NSMutableArray<CBCharacteristic *> *_subscriptions;
  NSInteger _attempts;
  NSInteger _enableVariant;
  NSMutableArray<NSData *> *_commandQueue;
  NSUInteger _reportCount;
  NSUInteger _responseCount;
  NSUInteger _foreignReportCount;
  BOOL _productChecked;
  CFAbsoluteTime _lastSummary;
  dispatch_source_t _setupTimer;
  dispatch_source_t _keepAliveTimer;

  // Wired controllers (macOS USB) only.
  BOOL _wired;
  NSUUID *_wiredIdentifier;
  NSString *_wiredName;
#if TARGET_OS_OSX
  IOHIDDeviceRef _hidDevice;
  uint32_t _usbLocation;
  IOUSBHostInterface *_usbInterface;
  IOUSBHostPipe *_usbCommandPipe;
#endif
}

- (instancetype)init {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (instancetype)initWithPeripheral:(CBPeripheral *)peripheral
                           manager:(NSOGCManager *)manager
                             queue:(dispatch_queue_t)queue
                     callbackQueue:(dispatch_queue_t)callbackQueue {
  self = [super init];
  if (self) {
    _peripheral = peripheral;
    _manager = manager;
    _queue = queue;
    _callbackQueue = callbackQueue;
    _lock = OS_UNFAIR_LOCK_INIT;
    _status = NSOGCControllerStatusConnecting;
    _playerIndex = 0;
    nsogc_calibration_default(&_calibration);
    _subscriptions = [NSMutableArray array];
    _commandQueue = [NSMutableArray array];
    peripheral.delegate = self;
  }
  return self;
}

#if TARGET_OS_OSX
- (instancetype)initWithHIDDevice:(IOHIDDeviceRef)device
                          manager:(NSOGCManager *)manager
                            queue:(dispatch_queue_t)queue
                    callbackQueue:(dispatch_queue_t)callbackQueue {
  self = [super init];
  if (self) {
    _manager = manager;
    _queue = queue;
    _callbackQueue = callbackQueue;
    _lock = OS_UNFAIR_LOCK_INIT;
    _status = NSOGCControllerStatusConnecting;
    _playerIndex = 0;
    nsogc_calibration_default(&_calibration);
    _subscriptions = [NSMutableArray array];
    _commandQueue = [NSMutableArray array];
    _wired = YES;
    _hidDevice = (IOHIDDeviceRef)CFRetain(device);
    NSString *product = (__bridge NSString *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    _wiredName = product.length ? product : @"NSO GameCube Controller";
    NSNumber *location = (__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDLocationIDKey));
    _usbLocation = location.unsignedIntValue;
    // Stable for a given USB port.
    uuid_t bytes = {'n', 's', 'o', 'g', 'c', '-', 'u', 's', 'b', 0, 0, 0, 0, 0, 0, 0};
    uint32_t port = _usbLocation;
    memcpy(bytes + 12, &port, sizeof port);
    _wiredIdentifier = [[NSUUID alloc] initWithUUIDBytes:bytes];
  }
  return self;
}

- (void)dealloc {
  if (_hidDevice != NULL)
    CFRelease(_hidDevice);
}

- (IOHIDDeviceRef)hidDevice {
  return _hidDevice;
}
#endif

#pragma mark - Public state

- (NSUUID *)identifier {
  return _wired ? _wiredIdentifier : _peripheral.identifier;
}

- (NSString *)name {
  if (_wired)
    return _wiredName;
  // Its Bluetooth name is literally "DeviceName" (NSOGCManager matches on it):
  // say what it is instead.
  NSString *name = _peripheral.name;
  return name.length && ![name isEqualToString:@"DeviceName"] ? name : @"NSO GameCube Controller";
}

- (BOOL)isWired {
  return _wired;
}

- (NSOGCControllerStatus)status {
  os_unfair_lock_lock(&_lock);
  NSOGCControllerStatus status = _status;
  os_unfair_lock_unlock(&_lock);
  return status;
}

- (void)setStatus:(NSOGCControllerStatus)status {
  os_unfair_lock_lock(&_lock);
  _status = status;
  os_unfair_lock_unlock(&_lock);
}

- (NSInteger)playerIndex {
  os_unfair_lock_lock(&_lock);
  NSInteger playerIndex = _playerIndex;
  os_unfair_lock_unlock(&_lock);
  return playerIndex;
}

- (nsogc_state)state {
  os_unfair_lock_lock(&_lock);
  nsogc_state state = _state;
  os_unfair_lock_unlock(&_lock);
  return state;
}

- (nsogc_raw_input)rawInput {
  os_unfair_lock_lock(&_lock);
  nsogc_raw_input raw = _raw;
  os_unfair_lock_unlock(&_lock);
  return raw;
}

- (nsogc_calibration)calibration {
  os_unfair_lock_lock(&_lock);
  nsogc_calibration calibration = _calibration;
  os_unfair_lock_unlock(&_lock);
  return calibration;
}

- (void)setCalibration:(nsogc_calibration)calibration {
  os_unfair_lock_lock(&_lock);
  _calibration = calibration;
  _centerCount = kCenterSamples;  // an explicit calibration replaces the automatic centre
  os_unfair_lock_unlock(&_lock);
}

- (NSOGCInputHandler)inputHandler {
  os_unfair_lock_lock(&_lock);
  NSOGCInputHandler handler = _inputHandler;
  os_unfair_lock_unlock(&_lock);
  return handler;
}

- (void)setInputHandler:(NSOGCInputHandler)inputHandler {
  NSOGCInputHandler copy = [inputHandler copy];
  os_unfair_lock_lock(&_lock);
  _inputHandler = copy;
  os_unfair_lock_unlock(&_lock);
}

- (void)setRumble:(BOOL)on {
  dispatch_async(_queue, ^{
    if (self->_step != NSOGCSetupStepReady)
      return;
    uint8_t frame[12];
    size_t length = nsogc_command_vibration(frame, on);
    [self enqueueCommand:[NSData dataWithBytes:frame length:length]];
  });
}

- (NSString *)logName {
  return [NSString stringWithFormat:@"%@ [%@]", self.name,
                                    [self.identifier.UUIDString substringToIndex:8]];
}

#pragma mark - Connection lifecycle (Bluetooth queue)

- (void)didConnect {
  [self setStatus:NSOGCControllerStatusInitializing];
  _step = NSOGCSetupStepDiscovering;
  [self startSetupTimer];
  [_manager log:@"%@: connected, discovering services", self.logName];
  [_peripheral discoverServices:nil];
}

- (void)didDisconnect {
  _step = NSOGCSetupStepIdle;
  [self cancelTimers];
  [_commandQueue removeAllObjects];
  _inputCharacteristic = nil;
#if TARGET_OS_OSX
  if (_wired) {
    [_usbInterface destroy];
    _usbInterface = nil;
    _usbCommandPipe = nil;
  }
#endif
  os_unfair_lock_lock(&_lock);
  _status = NSOGCControllerStatusDisconnected;
  memset(&_state, 0, sizeof _state);
  memset(&_raw, 0, sizeof _raw);
  nsogc_state state = _state;
  NSOGCInputHandler handler = _inputHandler;
  BOOL immediate = _manager.deliversInputOnBluetoothQueue;
  BOOL schedule = !immediate && !_deliveryPending && handler != nil;
  if (schedule)
    _deliveryPending = YES;
  os_unfair_lock_unlock(&_lock);
  // A neutral state releases every button the game still holds.
  if (immediate && handler != nil)
    handler(self, state);
  else if (schedule)
    dispatch_async(_callbackQueue, ^{ [self deliverLatestState]; });
}

- (void)assignPlayerIndex:(NSInteger)playerIndex {
  os_unfair_lock_lock(&_lock);
  _playerIndex = playerIndex;
  os_unfair_lock_unlock(&_lock);
  [self sendPlayerLeds];
}

- (void)fail:(NSString *)reason {
  if (_step == NSOGCSetupStepIdle)
    return;
  _step = NSOGCSetupStepIdle;
  [self cancelTimers];
  [_manager controllerDidFail:self reason:reason];
}

- (void)startSetupTimer {
  [self cancelTimers];
  _setupTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
  dispatch_source_set_timer(_setupTimer, dispatch_time(DISPATCH_TIME_NOW, kSetupTimeout),
                            DISPATCH_TIME_FOREVER, NSEC_PER_SEC);
  __weak NSOGCController *weakSelf = self;
  dispatch_source_set_event_handler(_setupTimer, ^{
    NSOGCController *strongSelf = weakSelf;
    if (strongSelf == nil || strongSelf->_step == NSOGCSetupStepReady)
      return;
    [strongSelf fail:[NSString stringWithFormat:@"setup timed out at step %ld",
                                                (long)strongSelf->_step]];
  });
  dispatch_resume(_setupTimer);
}

// Bluetooth only: the controller drops a link that sees no host traffic.
- (void)startKeepAlive {
  if (_wired || _keepAliveTimer != nil || _commandCharacteristic == nil)
    return;
  _keepAliveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
  dispatch_source_set_timer(_keepAliveTimer, dispatch_time(DISPATCH_TIME_NOW, kKeepAliveInterval),
                            kKeepAliveInterval, kKeepAliveInterval / 10);
  __weak NSOGCController *weakSelf = self;
  dispatch_source_set_event_handler(_keepAliveTimer, ^{
    [weakSelf sendPlayerLeds];
  });
  dispatch_resume(_keepAliveTimer);
}

- (void)cancelTimers {
  if (_setupTimer != nil) {
    dispatch_source_cancel(_setupTimer);
    _setupTimer = nil;
  }
  if (_keepAliveTimer != nil) {
    dispatch_source_cancel(_keepAliveTimer);
    _keepAliveTimer = nil;
  }
}

- (void)retryAfterDelay:(dispatch_block_t)block {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kRetryDelay), _queue, block);
}

#pragma mark - Setup steps

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
  if (_step != NSOGCSetupStepDiscovering)
    return;
  if (error != nil || peripheral.services.count == 0) {
    [self fail:[NSString stringWithFormat:@"service discovery failed: %@",
                                          error.localizedDescription ?: @"no services"]];
    return;
  }
  _pendingDiscoveries = peripheral.services.count;
  for (CBService *service in peripheral.services)
    [peripheral discoverCharacteristics:nil forService:service];
}

- (void)peripheral:(CBPeripheral *)peripheral
    didDiscoverCharacteristicsForService:(CBService *)service
                                   error:(NSError *)error {
  if (_step != NSOGCSetupStepDiscovering)
    return;
  if (error != nil)
    [_manager log:@"%@: characteristics of %@ failed: %@", self.logName,
                  service.UUID.UUIDString, error.localizedDescription];
  if (_pendingDiscoveries > 0)
    _pendingDiscoveries--;
  if (_pendingDiscoveries == 0)
    [self chooseCharacteristics];
}

- (void)chooseCharacteristics {
  CBUUID *controlService = [CBUUID UUIDWithString:kControlServiceUUID];
  CBUUID *nintendoService = [CBUUID UUIDWithString:kNintendoServiceUUID];
  CBUUID *nativeInput = [CBUUID UUIDWithString:kNativeInputUUID];
  CBCharacteristic *firstWritable = nil;
  _controlCharacteristic = nil;
  _commandCharacteristic = nil;
  _inputCharacteristic = nil;
  _nativeInputCharacteristic = nil;
  [_subscriptions removeAllObjects];

  for (CBService *service in _peripheral.services) {
    [_manager log:@"%@: service %@", self.logName, service.UUID.UUIDString];
    NSMutableArray<CBCharacteristic *> *withoutResponse = [NSMutableArray array];
    for (CBCharacteristic *characteristic in service.characteristics) {
      CBCharacteristicProperties properties = characteristic.properties;
      [_manager log:@"%@:   %@ [%@]", self.logName, characteristic.UUID.UUIDString,
                    NSOGCPropertyNames(properties)];
      if (properties & CBCharacteristicPropertyWrite) {
        if (firstWritable == nil)
          firstWritable = characteristic;
        if (_controlCharacteristic == nil && [service.UUID isEqual:controlService])
          _controlCharacteristic = characteristic;
      }
      if (properties & CBCharacteristicPropertyWriteWithoutResponse)
        [withoutResponse addObject:characteristic];
      if (properties & (CBCharacteristicPropertyNotify | CBCharacteristicPropertyIndicate))
        [_subscriptions addObject:characteristic];
      if ([characteristic.UUID isEqual:nativeInput])
        _nativeInputCharacteristic = characteristic;
    }
    // The Nintendo service has three write-without-response characteristics,
    // in handle order rumble, commands and commands with a rumble prefix.
    // CoreBluetooth lists characteristics in handle order.
    if (withoutResponse.count >= 3 &&
        (_commandCharacteristic == nil || [service.UUID isEqual:nintendoService]))
      _commandCharacteristic = withoutResponse[1];
  }

  if (_controlCharacteristic == nil)
    _controlCharacteristic = firstWritable;
  if (_controlCharacteristic == nil) {
    [self fail:@"no writable characteristic, this is not the controller"];
    return;
  }
  [_manager log:@"%@: control %@, commands %@, %lu to subscribe", self.logName,
                _controlCharacteristic.UUID.UUIDString,
                _commandCharacteristic.UUID.UUIDString ?: @"none (no LEDs or rumble)",
                (unsigned long)_subscriptions.count];

  _step = NSOGCSetupStepEnabling;
  _attempts = 0;
  _enableVariant = 0;
  [self writeEnable];
}

// The control characteristic takes exactly two bytes: 01 00, which some
// firmware wants as 01 01.
- (void)writeEnable {
  const uint8_t value[2] = {0x01, _enableVariant == 0 ? 0x00 : 0x01};
  [_peripheral writeValue:[NSData dataWithBytes:value length:sizeof value]
        forCharacteristic:_controlCharacteristic
                     type:CBCharacteristicWriteWithResponse];
}

- (void)peripheral:(CBPeripheral *)peripheral
    didWriteValueForCharacteristic:(CBCharacteristic *)characteristic
                             error:(NSError *)error {
  if (characteristic != _controlCharacteristic) {
    if (error != nil)
      [_manager log:@"%@: write to %@ failed: %@", self.logName,
                    characteristic.UUID.UUIDString, error.localizedDescription];
    return;
  }

  if (_step != NSOGCSetupStepEnabling)
    return;
  if (error != nil) {
    if (_enableVariant == 0) {
      _enableVariant = 1;
      [_manager log:@"%@: 01 00 not accepted (%@), trying 01 01", self.logName,
                    error.localizedDescription];
      [self writeEnable];
    } else if (++_attempts < kMaxAttempts) {
      [_manager log:@"%@: enable not accepted yet (%@), retrying", self.logName,
                    error.localizedDescription];
      _enableVariant = 0;
      [self retryAfterDelay:^{
        if (self->_step == NSOGCSetupStepEnabling)
          [self writeEnable];
      }];
    } else {
      [self fail:[NSString stringWithFormat:@"enable rejected: %@", error.localizedDescription]];
    }
    return;
  }
  [_manager log:@"%@: protocol enabled (01 %02X)", self.logName, _enableVariant == 0 ? 0x00 : 0x01];
  _step = NSOGCSetupStepSubscribing;
  _attempts = 0;
  [self subscribeNext];
}

- (void)subscribeNext {
  CBCharacteristic *next = _subscriptions.firstObject;
  if (next == nil) {
    [self configure];
    return;
  }
  [_peripheral setNotifyValue:YES forCharacteristic:next];
}

- (void)peripheral:(CBPeripheral *)peripheral
    didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic
                                          error:(NSError *)error {
  if (_step != NSOGCSetupStepSubscribing || characteristic != _subscriptions.firstObject)
    return;
  if (error != nil && ++_attempts < kMaxAttempts) {
    [_manager log:@"%@: subscription to %@ not accepted yet (%@), retrying", self.logName,
                  characteristic.UUID.UUIDString, error.localizedDescription];
    [self retryAfterDelay:^{
      if (self->_step == NSOGCSetupStepSubscribing &&
          self->_subscriptions.firstObject == characteristic)
        [self->_peripheral setNotifyValue:YES forCharacteristic:characteristic];
    }];
    return;
  }
  if (error != nil)
    [_manager log:@"%@: subscription to %@ failed: %@", self.logName,
                  characteristic.UUID.UUIDString, error.localizedDescription];
  else
    [_manager log:@"%@: subscribed to %@", self.logName, characteristic.UUID.UUIDString];
  [_subscriptions removeObjectAtIndex:0];
  _attempts = 0;
  [self subscribeNext];
}

// The device information read, the default report setting and the player
// LEDs go over the command channel; input reports start after them.
- (void)configure {
  _step = NSOGCSetupStepConfiguring;
  if (_commandCharacteristic == nil)
    [_manager log:@"%@: no command channel, waiting for input reports as is", self.logName];
  uint8_t frame[16];
  size_t length = nsogc_command_spi_read(frame, NSOGC_SPI_DEVICE_INFO, 0x40);
  [self enqueueCommand:[NSData dataWithBytes:frame length:length]];
  length = nsogc_command_default_report(frame);
  [self enqueueCommand:[NSData dataWithBytes:frame length:length]];
  [self sendPlayerLeds];
  [_manager log:@"%@: commands sent, waiting for input reports", self.logName];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), _queue, ^{
    if (self->_step == NSOGCSetupStepConfiguring)
      [self->_manager log:@"%@: no input report 5 s after setup", self.logName];
  });
}

- (void)becomeReady {
  if (_step == NSOGCSetupStepReady || _step == NSOGCSetupStepIdle)
    return;
  _step = NSOGCSetupStepReady;
  if (_setupTimer != nil) {
    dispatch_source_cancel(_setupTimer);
    _setupTimer = nil;
  }
  [self setStatus:NSOGCControllerStatusReady];
  [self startKeepAlive];
  [_manager controllerDidBecomeReady:self];
}

#pragma mark - Commands

- (void)sendPlayerLeds {
  uint8_t frame[16];
  size_t length = nsogc_command_player_leds(frame, nsogc_player_led_mask((int)self.playerIndex));
  [self enqueueCommand:[NSData dataWithBytes:frame length:length]];
}

- (void)enqueueCommand:(NSData *)command {
  if (_wired) {
    [self sendUSBCommand:command];
    return;
  }
  if (_commandCharacteristic == nil)
    return;
  if (_commandQueue.count >= kMaxQueuedCommands)
    [_commandQueue removeObjectAtIndex:0];
  [_commandQueue addObject:command];
  [self flushCommands];
}

- (void)flushCommands {
  if (_commandCharacteristic == nil)
    return;
  BOOL withResponse =
      (_commandCharacteristic.properties & CBCharacteristicPropertyWriteWithoutResponse) == 0;
  while (_commandQueue.count > 0) {
    if (!withResponse && !_peripheral.canSendWriteWithoutResponse)
      return;  // peripheralIsReadyToSendWriteWithoutResponse: resumes
    NSData *command = _commandQueue.firstObject;
    [_commandQueue removeObjectAtIndex:0];
    [_peripheral writeValue:command
          forCharacteristic:_commandCharacteristic
                       type:withResponse ? CBCharacteristicWriteWithResponse
                                         : CBCharacteristicWriteWithoutResponse];
  }
}

- (void)peripheralIsReadyToSendWriteWithoutResponse:(CBPeripheral *)peripheral {
  [self flushCommands];
}

#pragma mark - Notifications

- (void)peripheral:(CBPeripheral *)peripheral
    didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
                              error:(NSError *)error {
  if (error != nil)
    return;
  NSData *value = characteristic.value;
  // Input comes from one characteristic only: the native one when the
  // controller has it, else the first readable one that sends a report.
  BOOL reportStream = value.length >= NSOGC_MIN_INPUT_REPORT_SIZE &&
                      (characteristic.properties & CBCharacteristicPropertyRead);
  BOOL isInput = _nativeInputCharacteristic != nil
                     ? characteristic == _nativeInputCharacteristic
                     : reportStream && (_inputCharacteristic == nil ||
                                        characteristic == _inputCharacteristic);
  if (!isInput) {
    if (!reportStream)
      [self handleResponse:value from:characteristic];
    else if (_foreignReportCount++ < 2)
      [_manager log:@"%@: other report stream on %@: %@", self.logName,
                    characteristic.UUID.UUIDString, NSOGCHex(value, 24)];
    return;
  }
  if (_inputCharacteristic == nil) {
    _inputCharacteristic = characteristic;
    [_manager log:@"%@: input reports on %@ (%lu bytes)", self.logName,
                  characteristic.UUID.UUIDString, (unsigned long)value.length];
  }

  nsogc_raw_input raw;
  nsogc_report_format format = nsogc_parse_report(value.bytes, value.length, &raw);
  if (format == NSOGC_REPORT_INVALID)
    return;
  [self didReceiveInput:raw format:format bytes:value.bytes length:value.length];
}

// Both transports, once a report is decoded.
- (void)didReceiveInput:(nsogc_raw_input)raw
                 format:(nsogc_report_format)format
                  bytes:(const uint8_t *)bytes
                 length:(NSUInteger)length {
  if (_reportCount < 3)
    [_manager log:@"%@: report %lu (%@): %@", self.logName, (unsigned long)_reportCount + 1,
                  NSOGCFormatName(format), NSOGCHex([NSData dataWithBytes:bytes length:length], 24)];
  _reportCount++;
  [self acceptRawInput:raw];

  CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
  if (now - _lastSummary >= kSummaryInterval) {
    _lastSummary = now;
    [_manager log:@"%@: %lu reports; stick %u,%u c-stick %u,%u triggers %u,%u buttons 0x%06X",
                  self.logName, (unsigned long)_reportCount, raw.stick_x, raw.stick_y,
                  raw.cstick_x, raw.cstick_y, raw.trigger_l, raw.trigger_r, raw.buttons];
  }

  // Input already flowing means setup worked, whatever the last write said.
  if (_step == NSOGCSetupStepConfiguring) {
    [_manager log:@"%@: input reports arriving", self.logName];
    [self becomeReady];
  }
}

#pragma mark - USB (macOS)

#if TARGET_OS_OSX
// Interface 1 of the controller on this USB port.
static BOOL NSOGCIsCommandInterface(io_service_t service, uint32_t location) {
  NSNumber *vendor = CFBridgingRelease(
      IORegistryEntryCreateCFProperty(service, CFSTR("idVendor"), kCFAllocatorDefault, 0));
  NSNumber *product = CFBridgingRelease(
      IORegistryEntryCreateCFProperty(service, CFSTR("idProduct"), kCFAllocatorDefault, 0));
  NSNumber *number = CFBridgingRelease(
      IORegistryEntryCreateCFProperty(service, CFSTR("bInterfaceNumber"), kCFAllocatorDefault, 0));
  NSNumber *port = CFBridgingRelease(IORegistryEntrySearchCFProperty(
      service, kIOServicePlane, CFSTR("locationID"), kCFAllocatorDefault,
      kIORegistryIterateRecursively | kIORegistryIterateParents));
  return vendor.intValue == NSOGC_VENDOR_ID && product.intValue == NSOGC_PRODUCT_ID &&
         number.intValue == NSOGC_USB_COMMAND_INTERFACE &&
         (location == 0 || port.unsignedIntValue == location);
}

// Reports start once the default report command reaches interface 1's bulk
// OUT endpoint; HID only carries them in, to the manager (handleUSBReport:).
- (void)startWired {
  [self setStatus:NSOGCControllerStatusInitializing];
  _step = NSOGCSetupStepConfiguring;
  [self startSetupTimer];
  [_manager log:@"%@: connected over USB", self.logName];
  NSString *problem = [self openUSBCommandPipe];
  if (problem != nil) {
    [self fail:problem];
    return;
  }
  uint8_t frame[16];
  size_t length = nsogc_command_default_report(frame);
  [self enqueueCommand:[NSData dataWithBytes:frame length:length]];
  [self sendPlayerLeds];
  [_manager log:@"%@: commands sent over USB, waiting for input reports", self.logName];
}

- (NSString *)openUSBCommandPipe {
  io_iterator_t iterator = IO_OBJECT_NULL;
  if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostInterface"),
                                   &iterator) != KERN_SUCCESS)
    return @"cannot list USB interfaces";
  io_service_t service = IO_OBJECT_NULL;
  io_service_t candidate;
  while ((candidate = IOIteratorNext(iterator))) {
    if (service == IO_OBJECT_NULL && NSOGCIsCommandInterface(candidate, _usbLocation))
      service = candidate;
    else
      IOObjectRelease(candidate);
  }
  IOObjectRelease(iterator);
  if (service == IO_OBJECT_NULL)
    return @"USB interface 1 not found";

  NSError *error = nil;
  _usbInterface = [[IOUSBHostInterface alloc] initWithIOService:service
                                                        options:IOUSBHostObjectInitOptionsNone
                                                          queue:_queue
                                                          error:&error
                                                interestHandler:nil];
  IOObjectRelease(service);
  if (_usbInterface == nil)
    return [NSString stringWithFormat:@"cannot open USB interface 1: %@",
                                      error.localizedDescription];
  const IOUSBConfigurationDescriptor *configuration = _usbInterface.configurationDescriptor;
  const IOUSBInterfaceDescriptor *interface = _usbInterface.interfaceDescriptor;
  const IOUSBEndpointDescriptor *endpoint = NULL;
  while ((endpoint = IOUSBGetNextEndpointDescriptor(configuration, interface,
                                                    (const IOUSBDescriptorHeader *)endpoint))) {
    if (IOUSBGetEndpointType(endpoint) == kIOUSBEndpointTypeBulk &&
        IOUSBGetEndpointDirection(endpoint) == kIOUSBEndpointDirectionOut) {
      _usbCommandPipe = [_usbInterface copyPipeWithAddress:endpoint->bEndpointAddress error:&error];
      break;
    }
  }
  if (_usbCommandPipe == nil)
    return [NSString stringWithFormat:@"no bulk OUT endpoint on USB interface 1 (%@)",
                                      error.localizedDescription ?: @"none listed"];
  return nil;
}

- (void)handleUSBReport:(const uint8_t *)report length:(NSUInteger)length {
  if (_step == NSOGCSetupStepIdle)
    return;
  nsogc_raw_input raw;
  nsogc_report_format format = nsogc_parse_usb_report(report, length, &raw);
  if (format != NSOGC_REPORT_INVALID)
    [self didReceiveInput:raw format:format bytes:report length:length];
}
#endif

- (void)sendUSBCommand:(NSData *)command {
#if TARGET_OS_OSX
  if (_usbCommandPipe == nil)
    return;
  NSMutableData *frame = [command mutableCopy];
  nsogc_command_for_usb(frame.mutableBytes, frame.length);
  NSError *error = nil;
  __weak NSOGCController *weakSelf = self;
  BOOL queued = [_usbCommandPipe
      enqueueIORequestWithData:frame
             completionTimeout:1.0
                         error:&error
             completionHandler:^(IOReturn status, NSUInteger bytesTransferred) {
               (void)bytesTransferred;
               NSOGCController *strongSelf = weakSelf;
               if (status != kIOReturnSuccess && strongSelf != nil)
                 [strongSelf->_manager log:@"%@: USB command failed (0x%08X)", strongSelf.logName,
                                           status];
             }];
  if (!queued)
    [_manager log:@"%@: USB command not sent: %@", self.logName, error.localizedDescription];
#else
  (void)command;
#endif
}

- (void)handleResponse:(NSData *)value from:(CBCharacteristic *)characteristic {
  if (_responseCount++ < 8)
    [_manager log:@"%@: response on %@: %@", self.logName, characteristic.UUID.UUIDString,
                  NSOGCHex(value, 32)];
  uint16_t product = 0;
  if (!_productChecked && nsogc_find_vendor_product(value.bytes, value.length, &product)) {
    _productChecked = YES;
    if (product == NSOGC_PRODUCT_ID)
      [_manager log:@"%@: device information confirms the GameCube controller", self.logName];
    else
      [_manager log:@"%@: device information reports product 0x%04X, not the GameCube "
                    @"controller; buttons may be mapped differently",
                    self.logName, product];
  }
}

- (void)acceptRawInput:(nsogc_raw_input)raw {
  BOOL centered = NO;
  os_unfair_lock_lock(&_lock);
  if (_centerCount < kCenterSamples) {
    BOOL atRest = fabsf(raw.stick_x - 2048.0f) < kCenterTolerance &&
                  fabsf(raw.stick_y - 2048.0f) < kCenterTolerance &&
                  fabsf(raw.cstick_x - 2048.0f) < kCenterTolerance &&
                  fabsf(raw.cstick_y - 2048.0f) < kCenterTolerance;
    if (atRest) {
      _centerSum[0] += raw.stick_x;
      _centerSum[1] += raw.stick_y;
      _centerSum[2] += raw.cstick_x;
      _centerSum[3] += raw.cstick_y;
      if (++_centerCount == kCenterSamples) {
        _calibration.stick_center_x = (float)(_centerSum[0] / kCenterSamples);
        _calibration.stick_center_y = (float)(_centerSum[1] / kCenterSamples);
        _calibration.cstick_center_x = (float)(_centerSum[2] / kCenterSamples);
        _calibration.cstick_center_y = (float)(_centerSum[3] / kCenterSamples);
        centered = YES;
      }
    } else {
      _centerCount = kCenterSamples;  // a stick is held: keep the default centres
    }
  }
  _raw = raw;
  nsogc_normalize(&_raw, &_calibration, &_state);
  nsogc_calibration calibration = _calibration;
  nsogc_state state = _state;
  NSOGCInputHandler handler = _inputHandler;
  BOOL immediate = _manager.deliversInputOnBluetoothQueue;
  BOOL schedule = !immediate && !_deliveryPending && handler != nil;
  if (schedule)
    _deliveryPending = YES;
  os_unfair_lock_unlock(&_lock);

  if (centered)
    [_manager log:@"%@: stick centres %.0f,%.0f, c-stick %.0f,%.0f", self.logName,
                  calibration.stick_center_x, calibration.stick_center_y,
                  calibration.cstick_center_x, calibration.cstick_center_y];
  if (immediate && handler != nil)
    handler(self, state);
  else if (schedule)
    dispatch_async(_callbackQueue, ^{ [self deliverLatestState]; });
}

- (void)deliverLatestState {
  os_unfair_lock_lock(&_lock);
  nsogc_state state = _state;
  NSOGCInputHandler handler = _inputHandler;
  _deliveryPending = NO;
  os_unfair_lock_unlock(&_lock);
  if (handler != nil)
    handler(self, state);
}

@end
