#import "SunPadTVControllerManager.h"

@interface SunPadCoreHost : NSObject
- (void)publishInput:(SunPadInputState)input;
@end

#include <cmath>

static SunPadPhysicalControllerButton SunPadTVPressedFaceButtons(
    GCExtendedGamepad *gamepad) {
    uint8_t buttons = 0;
    if (gamepad.buttonA.isPressed) buttons |= SunPadPhysicalControllerButtonA;
    if (gamepad.buttonB.isPressed) buttons |= SunPadPhysicalControllerButtonB;
    if (gamepad.buttonX.isPressed) buttons |= SunPadPhysicalControllerButtonX;
    if (gamepad.buttonY.isPressed) buttons |= SunPadPhysicalControllerButtonY;
    if (gamepad.leftShoulder.isPressed)
        buttons |= SunPadPhysicalControllerButtonLeftShoulder;
    return (SunPadPhysicalControllerButton)buttons;
}

static int8_t SunPadTVAxisValue(float value) {
    return (int8_t)std::lround(value * 127.0f);
}

static uint8_t SunPadTVTriggerValue(float value) {
    return (uint8_t)std::lround(value * 255.0f);
}

SunPadInputState SunPadTVInputStateFromExtendedGamepad(
    GCExtendedGamepad *gamepad,
    SunPadControllerButtonMapping mapping) {
    SunPadInputState state = {};
    if (gamepad == nil)
        return state;

    state.connected = 1;
    state.buttons = SunPadApplyControllerButtonMapping(
        mapping, SunPadTVPressedFaceButtons(gamepad));
    if (gamepad.buttonMenu.isPressed) state.buttons |= SunPadButtonStart;
    if (gamepad.dpad.up.isPressed) state.buttons |= SunPadButtonDpadUp;
    if (gamepad.dpad.down.isPressed) state.buttons |= SunPadButtonDpadDown;
    if (gamepad.dpad.left.isPressed) state.buttons |= SunPadButtonDpadLeft;
    if (gamepad.dpad.right.isPressed) state.buttons |= SunPadButtonDpadRight;
    state.stickX = SunPadTVAxisValue(gamepad.leftThumbstick.xAxis.value);
    state.stickY = SunPadTVAxisValue(gamepad.leftThumbstick.yAxis.value);
    state.cStickX = SunPadTVAxisValue(gamepad.rightThumbstick.xAxis.value);
    state.cStickY = SunPadTVAxisValue(gamepad.rightThumbstick.yAxis.value);
    state.triggerL = SunPadTVTriggerValue(gamepad.leftTrigger.value);
    uint8_t physicalTriggerR = SunPadTVTriggerValue(gamepad.rightTrigger.value);
    state.triggerR = SunPadControllerRightTriggerPressure(
        physicalTriggerR, gamepad.rightShoulder.isPressed);
    if (state.triggerL > 30) state.buttons |= SunPadButtonL;
    if (physicalTriggerR > 30) state.buttons |= SunPadButtonR;
    return state;
}

@interface SunPadTVControllerManager () {
    __weak SunPadCoreHost *_host;
    GCController *_playerOne;
    BOOL _started;
    BOOL _active;
}
@end

@implementation SunPadTVControllerManager

- (instancetype)initWithHost:(SunPadCoreHost *)host {
    if ((self = [super init])) {
        _host = host;
    }
    return self;
}

- (void)start {
    if (_started)
        return;
    _started = YES;
    _active = YES;
    [self addControllerObservers];
    [self reconcileControllers];
}

- (void)activate {
    if (!_started || _active)
        return;
    _active = YES;
    [self addControllerObservers];
    [self reconcileControllers];
}

- (void)deactivate {
    _active = NO;
    [self removeControllerObservers];
    [self removePlayerOneHandler];
    [self publishDisconnectedState];
}

- (void)stop {
    _started = NO;
    _active = NO;
    [self removeControllerObservers];
    [self removePlayerOneHandler];
    [self publishDisconnectedState];
}

- (void)addControllerObservers {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self
               selector:@selector(controllerDidConnect:)
                   name:GCControllerDidConnectNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(controllerDidDisconnect:)
                   name:GCControllerDidDisconnectNotification
                 object:nil];
}

- (void)removeControllerObservers {
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                    name:GCControllerDidConnectNotification
                                                  object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                    name:GCControllerDidDisconnectNotification
                                                  object:nil];
}

- (void)controllerDidConnect:(NSNotification *)notification {
    (void)notification;
    if (_active)
        [self reconcileControllers];
}

- (void)controllerDidDisconnect:(NSNotification *)notification {
    (void)notification;
    if (!_active)
        return;
    [self removePlayerOneHandler];
    [self publishDisconnectedState];
    [self reconcileControllers];
}

- (void)removePlayerOneHandler {
    _playerOne.extendedGamepad.valueChangedHandler = nil;
    _playerOne.playerIndex = GCControllerPlayerIndexUnset;
    _playerOne = nil;
}

- (void)publishDisconnectedState {
    SunPadCoreHost *host = _host;
    if (host != nil)
        [host publishInput:(SunPadInputState){0}];
}

- (void)publishPlayerOneState {
    GCController *controller = _playerOne;
    SunPadCoreHost *host = _host;
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    if (host != nil && gamepad != nil) {
        [host publishInput:SunPadTVInputStateFromExtendedGamepad(
            gamepad, [SunPadControllerMappingStore mapping])];
    }
}

- (void)reconcileControllers {
    if (!_active)
        return;

    GCController *firstExtendedController = nil;
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil) {
            firstExtendedController = controller;
            break;
        }
    }

    if (firstExtendedController != _playerOne) {
        [self removePlayerOneHandler];
        _playerOne = firstExtendedController;
        _playerOne.playerIndex = GCControllerPlayerIndex1;
        __weak SunPadTVControllerManager *weakSelf = self;
        _playerOne.extendedGamepad.valueChangedHandler =
            ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
                (void)element;
                SunPadTVControllerManager *strongSelf = weakSelf;
                if (strongSelf == nil || !strongSelf->_active)
                    return;
                SunPadCoreHost *host = strongSelf->_host;
                if (host != nil)
                    [host publishInput:SunPadTVInputStateFromExtendedGamepad(
                        gamepad, [SunPadControllerMappingStore mapping])];
            };
    }

    if (_playerOne != nil)
        [self publishPlayerOneState];
}

@end
