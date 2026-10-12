#import "SunPadControllerRumble.h"

#import <CoreHaptics/CoreHaptics.h>
#import <GameController/GameController.h>

#include <atomic>

#import "SunPadDiagnostics.h"

@implementation SunPadControllerRumble {
    dispatch_queue_t _queue;
    GCController *_controller;           // main thread
    CHHapticEngine *_engine;             // _queue
    id<CHHapticPatternPlayer> _player;   // _queue
    std::atomic<bool> _allowed;
    std::atomic<bool> _supported;
    std::atomic<bool> _requested;
    std::atomic<bool> _needsRestart;
    std::atomic<bool> _loggedActive;
}

+ (instancetype)sharedRumble {
    static SunPadControllerRumble *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [SunPadControllerRumble new];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init]))
        _queue = dispatch_queue_create("com.sunpad.controller-rumble", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (BOOL)allowed {
    return _allowed.load();
}

- (void)setAllowed:(BOOL)allowed {
    if (_allowed.exchange(allowed) == static_cast<bool>(allowed))
        return;
    SunPadLog(@"controller rumble allowed=%d", allowed);
    if (!allowed)
        [self stopPlayer];
}

- (void)useController:(GCController *)controller {
    if (controller == _controller && !_needsRestart.load())
        return;
    _controller = controller;
    _needsRestart.store(false);
    _supported.store(false);
    _requested.store(false);
    dispatch_async(_queue, ^{
        [self teardownOnQueue];
        if (controller == nil)
            return;
        if (controller.haptics == nil) {
            SunPadLog(@"controller rumble unavailable reason=no haptics vendor=%@",
                      controller.vendorName ?: @"unknown");
            return;
        }
        CHHapticEngine *engine =
            [controller.haptics createEngineWithLocality:GCHapticsLocalityDefault];
        if (engine == nil) {
            SunPadLog(@"controller rumble unavailable reason=no haptics engine");
            return;
        }
        engine.playsHapticsOnly = YES;
        NSError *error = nil;
        if (![engine startAndReturnError:&error]) {
            SunPadLog(@"controller rumble engine start failed error=%@",
                      error.localizedDescription ?: @"unknown");
            return;
        }
        // One continuous, strong and soft event, like the GameCube's single motor.
        CHHapticEvent *event = [[CHHapticEvent alloc]
            initWithEventType:CHHapticEventTypeHapticContinuous
                   parameters:@[
                       [[CHHapticEventParameter alloc]
                           initWithParameterID:CHHapticEventParameterIDHapticIntensity
                                         value:1.0f],
                       [[CHHapticEventParameter alloc]
                           initWithParameterID:CHHapticEventParameterIDHapticSharpness
                                         value:0.1f],
                   ]
                 relativeTime:0.0
                     duration:GCHapticDurationInfinite];
        CHHapticPattern *pattern =
            [[CHHapticPattern alloc] initWithEvents:@[event] parameters:@[] error:&error];
        id<CHHapticPatternPlayer> player =
            pattern == nil ? nil : [engine createPlayerWithPattern:pattern error:&error];
        if (player == nil) {
            SunPadLog(@"controller rumble player unavailable error=%@",
                      error.localizedDescription ?: @"unknown");
            [engine stopWithCompletionHandler:nil];
            return;
        }
        // iOS stops the engine in the background and after a haptics server
        // reset; the next reconcile builds a new one.
        __weak SunPadControllerRumble *weakSelf = self;
        __weak CHHapticEngine *weakEngine = engine;
        void (^markStopped)(NSString *) = ^(NSString *reason) {
            SunPadControllerRumble *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            dispatch_async(strongSelf->_queue, ^{
                if (strongSelf->_engine != weakEngine)
                    return;
                strongSelf->_supported.store(false);
                strongSelf->_requested.store(false);
                strongSelf->_needsRestart.store(true);
                SunPadLog(@"controller rumble stopped reason=%@", reason);
            });
        };
        engine.stoppedHandler = ^(CHHapticEngineStoppedReason reason) {
            markStopped([NSString stringWithFormat:@"%ld", (long)reason]);
        };
        engine.resetHandler = ^{
            markStopped(@"reset");
        };
        self->_engine = engine;
        self->_player = player;
        self->_supported.store(true);
        SunPadLog(@"controller rumble ready vendor=%@", controller.vendorName ?: @"unknown");
    });
}

- (BOOL)setRumbleEnabled:(BOOL)enabled {
    if (!_allowed.load() || !_supported.load())
        return NO;
    if (_requested.exchange(enabled) == static_cast<bool>(enabled))
        return YES;
    dispatch_async(_queue, ^{
        NSError *error = nil;
        BOOL success = enabled
            ? [self->_player startAtTime:CHHapticTimeImmediate error:&error]
            : [self->_player stopAtTime:CHHapticTimeImmediate error:&error];
        if (!success) {
            self->_supported.store(false);
            self->_needsRestart.store(true);
            SunPadLog(@"controller rumble failed error=%@",
                      error.localizedDescription ?: @"unknown");
        } else if (enabled && !self->_loggedActive.exchange(true)) {
            SunPadLog(@"controller rumble active");
        }
    });
    return YES;
}

- (void)stopPlayer {
    _requested.store(false);
    dispatch_async(_queue, ^{
        [self->_player stopAtTime:CHHapticTimeImmediate error:nil];
    });
}

- (void)teardownOnQueue {
    _engine.stoppedHandler = ^(CHHapticEngineStoppedReason reason) { (void)reason; };
    _engine.resetHandler = ^{};
    [_player stopAtTime:CHHapticTimeImmediate error:nil];
    [_engine stopWithCompletionHandler:nil];
    _player = nil;
    _engine = nil;
}

@end

// Weakly imported by RecompCore's Pad::Rumble and Pad::ResetRumble for pad 0
// on iOS and iPadOS. Called on the emulation thread.
extern "C" bool SunPadSetRumble(bool enabled) {
    @autoreleasepool {
        return [[SunPadControllerRumble sharedRumble] setRumbleEnabled:enabled];
    }
}
