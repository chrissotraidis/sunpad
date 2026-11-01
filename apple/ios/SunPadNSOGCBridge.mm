#import "SunPadNSOGCBridge.h"

#import "NSOGC/NSOGCKit.h"
#import "SunPadControllerRumble.h"
#import "SunPadDiagnostics.h"
#import "SunPadInputMixer.h"

#include <atomic>
#include <cmath>

static NSString *const kEnabledKey = @"SunPadNSOGCEnabled";

// The controller is a GameCube pad, so its buttons map one to one; the
// player's face-button mapping is for other layouts. L and R are the
// triggers' own end-of-travel clicks, as on the original controller.
static SunPadInputState SunPadInputStateFromNSOGC(const nsogc_state &pad) {
    static const struct {
        uint32_t pad;
        uint16_t sunpad;
    } kButtons[] = {
        {NSOGC_BUTTON_A, SunPadButtonA},
        {NSOGC_BUTTON_B, SunPadButtonB},
        {NSOGC_BUTTON_X, SunPadButtonX},
        {NSOGC_BUTTON_Y, SunPadButtonY},
        {NSOGC_BUTTON_Z, SunPadButtonZ},
        {NSOGC_BUTTON_START, SunPadButtonStart},
        {NSOGC_BUTTON_L, SunPadButtonL},
        {NSOGC_BUTTON_R, SunPadButtonR},
        {NSOGC_BUTTON_DPAD_UP, SunPadButtonDpadUp},
        {NSOGC_BUTTON_DPAD_DOWN, SunPadButtonDpadDown},
        {NSOGC_BUTTON_DPAD_LEFT, SunPadButtonDpadLeft},
        {NSOGC_BUTTON_DPAD_RIGHT, SunPadButtonDpadRight},
    };
    SunPadInputState state = {};
    state.connected = 1;
    for (const auto &button : kButtons) {
        if (pad.buttons & button.pad)
            state.buttons |= button.sunpad;
    }
    state.stickX = (int8_t)std::lround(pad.stick_x * 127.0f);
    state.stickY = (int8_t)std::lround(pad.stick_y * 127.0f);
    state.cStickX = (int8_t)std::lround(pad.cstick_x * 127.0f);
    state.cStickY = (int8_t)std::lround(pad.cstick_y * 127.0f);
    state.triggerL = (uint8_t)std::lround(pad.trigger_l * 255.0f);
    state.triggerR = (uint8_t)std::lround(pad.trigger_r * 255.0f);
    return state;
}

@interface SunPadNSOGCBridge () <NSOGCManagerDelegate>
@end

@implementation SunPadNSOGCBridge {
    NSOGCController *_controller;
    BOOL _bluetoothAvailable;
}

+ (instancetype)sharedBridge {
    static SunPadNSOGCBridge *bridge;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bridge = [[SunPadNSOGCBridge alloc] init];
    });
    return bridge;
}

- (instancetype)init {
    if ((self = [super init])) {
        [NSUserDefaults.standardUserDefaults registerDefaults:@{kEnabledKey : @YES}];
        _bluetoothAvailable = YES;
    }
    return self;
}

- (BOOL)enabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:kEnabledKey];
}

- (void)setEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kEnabledKey];
}

- (void)start {
    if (self.enabled)
        [self startManager];
}

- (void)startManager {
    NSOGCManager *manager = NSOGCManager.sharedManager;
    manager.maximumControllers = 1;  // SunPad has one player
    // Input goes straight from the Bluetooth queue into the locked mixer.
    manager.deliversInputOnBluetoothQueue = YES;
    if (manager.delegate != self) {
        manager.delegate = self;
        manager.logHandler = ^(NSString *line) {
            SunPadLog(@"nsogc %@", line);
        };
        [self adoptControllersOfManager:manager];
    }
    [manager start];
}

// Another part of an app that embeds SunPad may have used the manager
// meanwhile: catch up with a disconnection, and give the controller its
// handler back.
- (void)adoptControllersOfManager:(NSOGCManager *)manager {
    NSArray<NSOGCController *> *ready = manager.controllers;
    NSOGCController *previous = _controller;
    if (previous != nil && ![ready containsObject:previous])
        [self manager:manager didDisconnectController:previous];
    _controller = nil;
    NSOGCController *controller = [ready containsObject:previous] ? previous : ready.firstObject;
    if (controller != nil)
        [self manager:manager didConnectController:controller];
}

// Any queue.
- (void)homeButtonPressed {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.homeButtonHandler != nil)
            self.homeButtonHandler();
    });
}

- (void)connect {
    self.enabled = YES;
    [self startManager];
    SunPadLog(@"nsogc turned on");
    [self notifyConnectionChanged];
}

- (void)disconnect {
    self.enabled = NO;
    [NSOGCManager.sharedManager stop];
    SunPadLog(@"nsogc turned off");
    [self notifyConnectionChanged];
}

- (void)forgetController {
    NSOGCManager *manager = NSOGCManager.sharedManager;
    [manager forgetControllers];
    // Forgotten first, so the disconnection does not wait for it to come back.
    if (_controller != nil)
        [manager disconnectController:_controller];
    SunPadLog(@"nsogc controller forgotten");
    [self notifyConnectionChanged];
}

- (SunPadNSOGCStatus)status {
    if (!self.enabled)
        return SunPadNSOGCStatusOff;
    if (_controller != nil)
        return SunPadNSOGCStatusConnected;
    if (!_bluetoothAvailable)
        return SunPadNSOGCStatusUnavailable;
    return SunPadNSOGCStatusSearching;
}

- (BOOL)controllerConnected {
    return _controller != nil;
}

- (NSString *)controllerName {
    return _controller.name;
}

- (BOOL)hasRememberedController {
    return NSOGCManager.sharedManager.hasRememberedControllers;
}

- (void)notifyConnectionChanged {
    if (self.connectionChangedHandler != nil)
        self.connectionChangedHandler();
}

#pragma mark - NSOGCManagerDelegate (main thread)

- (void)manager:(NSOGCManager *)manager didConnectController:(NSOGCController *)controller {
    if (_controller != nil)
        return;
    _controller = controller;
    void (^inputUpdated)(void) = self.inputUpdatedHandler;
    __weak SunPadNSOGCBridge *weakSelf = self;
    __block uint32_t previousButtons = 0;
    // Runs on the Bluetooth queue for every report.
    controller.inputHandler = ^(NSOGCController *source, nsogc_state state) {
        (void)source;
        [[SunPadInputMixer sharedMixer] setInputState:SunPadInputStateFromNSOGC(state)
                                            fromTouch:NO];
        if (inputUpdated != nil)
            inputUpdated();
        uint32_t pressed = state.buttons & ~previousButtons;
        previousButtons = state.buttons;
        if (pressed & NSOGC_BUTTON_HOME)
            [weakSelf homeButtonPressed];
    };
    SunPadLog(@"nsogc controller connected name=%@", controller.name);
    [self notifyConnectionChanged];
}

- (void)manager:(NSOGCManager *)manager didDisconnectController:(NSOGCController *)controller {
    if (controller != _controller)
        return;
    controller.inputHandler = nil;
    _controller = nil;
    [[SunPadInputMixer sharedMixer] clearInputFromTouch:NO];
    SunPadLog(@"nsogc controller disconnected");
    [self notifyConnectionChanged];
}

- (void)manager:(NSOGCManager *)manager bluetoothAvailabilityDidChange:(BOOL)available {
    _bluetoothAvailable = available;
    [self notifyConnectionChanged];
}

@end

// Replaces the weak default in SunPadControllerRumble.mm. Called on the
// emulation thread for player one's rumble; true when the NSO controller is
// connected and took it.
extern "C" bool SunPadNSOGCSetRumble(bool enabled) {
    static std::atomic<int> requested{-1};
    NSOGCController *controller = NSOGCManager.sharedManager.controllers.firstObject;
    if (controller == nil) {
        requested.store(-1);
        return false;
    }
    if (![SunPadControllerRumble sharedRumble].allowed)
        enabled = false;
    int value = enabled ? 1 : 0;
    if (requested.exchange(value) != value)
        [controller setRumble:enabled];
    return true;
}
