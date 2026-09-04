#import <CommonCrypto/CommonDigest.h>
#import <CoreHaptics/CoreHaptics.h>
#import <GameController/GameController.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#import "SunPadControllerMapping.h"
#import "SunPadCoreHost.h"
#import "SunPadDiagnostics.h"
#import "SunPadSettings.h"

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>

namespace {

NSString *const SunPadTVMainDOLSHA256 =
    @"13934c863d649b1ddca1ca4d7748f49d28a571685cbee5fb1542545c32869955";

struct SunPadTVPadSnapshot {
    uint16_t buttons;
    uint8_t stickX;
    uint8_t stickY;
    uint8_t cStickX;
    uint8_t cStickY;
    uint8_t triggerL;
    uint8_t triggerR;
    uint8_t analogA;
    uint8_t analogB;
    int32_t connected;
};
static_assert(sizeof(SunPadTVPadSnapshot) == 16);

NSString *SunPadTVSupportRoot(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        NSCachesDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"SunPad"];
}

NSString *SunPadTVGameRoot(void) {
    return [SunPadTVSupportRoot()
        stringByAppendingPathComponent:@"GameData/GMSE01"];
}

NSString *SunPadTVSHA256(NSString *path, NSError **error) {
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
    if (stream == nil)
        return nil;
    [stream open];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    NSMutableData *buffer = [NSMutableData dataWithLength:1024 * 1024];
    for (;;) {
        NSInteger count = [stream read:static_cast<uint8_t *>(buffer.mutableBytes)
                              maxLength:buffer.length];
        if (count < 0) {
            if (error != nullptr)
                *error = stream.streamError;
            [stream close];
            return nil;
        }
        if (count == 0)
            break;
        CC_SHA256_Update(&context, buffer.bytes, static_cast<CC_LONG>(count));
    }
    [stream close];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex =
        [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index)
        [hex appendFormat:@"%02x", digest[index]];
    return hex;
}

NSString *SunPadTVValidateGameData(NSError **error) {
    NSString *root = SunPadTVGameRoot();
    NSArray<NSString *> *required = @[
        @"sys/boot.bin", @"sys/bi2.bin", @"sys/apploader.img", @"sys/fst.bin",
        @"sys/main.dol", @"files/opening.bnr", @"files/AudioRes/mSound.asn",
        @"files/data/common.szs",
    ];
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *relative in required) {
        BOOL directory = NO;
        NSString *path = [root stringByAppendingPathComponent:relative];
        if (![files fileExistsAtPath:path isDirectory:&directory] || directory ||
            ![files isReadableFileAtPath:path]) {
            return [NSString stringWithFormat:@"Missing %@.", relative];
        }
    }
    NSData *boot = [NSData dataWithContentsOfFile:
        [root stringByAppendingPathComponent:@"sys/boot.bin"] options:0 error:error];
    if (boot.length < 0x20)
        return @"sys/boot.bin is missing or truncated.";
    const uint8_t *bytes = static_cast<const uint8_t *>(boot.bytes);
    if (std::memcmp(bytes, "GMSE01", 6) != 0 || bytes[6] != 0 || bytes[7] != 0)
        return @"SunPad supports GMSE01 USA, disc 0, revision 0 only.";
    const uint32_t magic = (static_cast<uint32_t>(bytes[0x1c]) << 24) |
                           (static_cast<uint32_t>(bytes[0x1d]) << 16) |
                           (static_cast<uint32_t>(bytes[0x1e]) << 8) |
                           static_cast<uint32_t>(bytes[0x1f]);
    if (magic != 0xc2339f3du)
        return @"The GameCube disc header is invalid.";
    NSString *hash = SunPadTVSHA256(
        [root stringByAppendingPathComponent:@"sys/main.dol"], error);
    if (error != nullptr && *error != nil)
        return nil;
    if (![hash isEqualToString:SunPadTVMainDOLSHA256])
        return @"sys/main.dol does not match supported GMSE01 revision 0 data.";
    return nil;
}

SunPadPhysicalControllerButton SunPadTVPressedFaceButtons(
    GCExtendedGamepad *gamepad) {
    uint8_t buttons = 0;
    if (gamepad.buttonA.isPressed) buttons |= SunPadPhysicalControllerButtonA;
    if (gamepad.buttonB.isPressed) buttons |= SunPadPhysicalControllerButtonB;
    if (gamepad.buttonX.isPressed) buttons |= SunPadPhysicalControllerButtonX;
    if (gamepad.buttonY.isPressed) buttons |= SunPadPhysicalControllerButtonY;
    if (gamepad.leftShoulder.isPressed)
        buttons |= SunPadPhysicalControllerButtonLeftShoulder;
    return static_cast<SunPadPhysicalControllerButton>(buttons);
}

SunPadInputState SunPadTVInputStateFromGamepad(GCExtendedGamepad *gamepad) {
    SunPadInputState state = {};
    if (gamepad == nil)
        return state;
    state.connected = 1;
    state.buttons = SunPadApplyControllerButtonMapping(
        SunPadControllerMappingStore.mapping,
        SunPadTVPressedFaceButtons(gamepad));
    if (gamepad.buttonMenu.isPressed) state.buttons |= SunPadButtonStart;
    if (gamepad.dpad.up.isPressed) state.buttons |= SunPadButtonDpadUp;
    if (gamepad.dpad.down.isPressed) state.buttons |= SunPadButtonDpadDown;
    if (gamepad.dpad.left.isPressed) state.buttons |= SunPadButtonDpadLeft;
    if (gamepad.dpad.right.isPressed) state.buttons |= SunPadButtonDpadRight;
    state.stickX = static_cast<int8_t>(
        std::lround(gamepad.leftThumbstick.xAxis.value * 127.0f));
    state.stickY = static_cast<int8_t>(
        std::lround(gamepad.leftThumbstick.yAxis.value * 127.0f));
    state.cStickX = static_cast<int8_t>(
        std::lround(gamepad.rightThumbstick.xAxis.value * 127.0f));
    state.cStickY = static_cast<int8_t>(
        std::lround(gamepad.rightThumbstick.yAxis.value * 127.0f));
    state.triggerL = static_cast<uint8_t>(
        std::lround(gamepad.leftTrigger.value * 255.0f));
    uint8_t physicalR = static_cast<uint8_t>(
        std::lround(gamepad.rightTrigger.value * 255.0f));
    state.triggerR = SunPadControllerRightTriggerPressure(
        physicalR, gamepad.rightShoulder.isPressed);
    if (state.triggerL > 30) state.buttons |= SunPadButtonL;
    if (physicalR > 30) state.buttons |= SunPadButtonR;
    return state;
}

SunPadTVPadSnapshot SunPadTVSnapshotFromInputState(
    SunPadInputState state, BOOL modernCStickHorizontal) {
    SunPadTVPadSnapshot snapshot = {};
    snapshot.buttons = state.buttons;
    snapshot.stickX = static_cast<uint8_t>(128 + state.stickX);
    snapshot.stickY = static_cast<uint8_t>(128 + state.stickY);
    snapshot.cStickX = static_cast<uint8_t>(
        128 + (modernCStickHorizontal ? -state.cStickX : state.cStickX));
    snapshot.cStickY = static_cast<uint8_t>(128 + state.cStickY);
    snapshot.triggerL = state.triggerL;
    snapshot.triggerR = state.triggerR;
    snapshot.analogA = (state.buttons & SunPadButtonA) != 0 ? 255 : 0;
    snapshot.analogB = (state.buttons & SunPadButtonB) != 0 ? 255 : 0;
    snapshot.connected = state.connected;
    return snapshot;
}

}  // namespace

@interface SunPadTVMetalView : UIView
@end

@implementation SunPadTVMetalView
+ (Class)layerClass { return CAMetalLayer.class; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.blackColor;
        self.opaque = YES;
        CAMetalLayer *layer = (CAMetalLayer *)self.layer;
        layer.device = MTLCreateSystemDefaultDevice();
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.framebufferOnly = YES;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    layer.drawableSize = CGSizeMake(CGRectGetWidth(self.bounds) * self.contentScaleFactor,
                                    CGRectGetHeight(self.bounds) * self.contentScaleFactor);
}
@end

@interface SunPadTVViewController : UIViewController {
@private
    std::mutex _padMutex;
    SunPadTVPadSnapshot _padSnapshot;
    dispatch_queue_t _hapticsQueue;
    CHHapticEngine *_hapticEngine;
    id<CHHapticAdvancedPatternPlayer> _rumblePlayer;
    std::atomic<bool> _rumbleSupported;
    std::atomic<bool> _rumbleRequested;
    std::atomic<bool> _rumbleBridgeLogged;
    BOOL _modernCStickHorizontal;
}
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIStackView *actions;
@property(nonatomic, strong) SunPadCoreHost *coreHost;
@property(nonatomic, strong) GCController *controller;
@property(nonatomic, assign) BOOL controllerInputActive;
- (void)attemptStart;
- (void)updatePadSnapshot:(SunPadInputState)state;
- (void)configureRumbleForController:(GCController *)controller;
- (void)teardownRumble;
- (BOOL)readPadSnapshot:(void *)buffer size:(size_t)size;
- (BOOL)setRumbleEnabled:(BOOL)enabled;
- (void)pauseRuntime;
- (void)resumeRuntime;
- (void)stopRuntime;
@end

static __weak SunPadTVViewController *SunPadTVActiveController;

extern "C" bool SunPadTVReadPadSnapshot(void *buffer, size_t size) {
    return [SunPadTVActiveController readPadSnapshot:buffer size:size];
}

extern "C" bool SunPadTVSetRumble(bool enabled) {
    return [SunPadTVActiveController setRumbleEnabled:enabled];
}

@implementation SunPadTVViewController

- (void)loadView {
    _hapticsQueue = dispatch_queue_create(
        "com.sunpad.tv.controller-haptics", DISPATCH_QUEUE_SERIAL);
    _modernCStickHorizontal =
        SunPadSettings.sharedSettings.modernCStickHorizontal;
    SunPadTVMetalView *root = [[SunPadTVMetalView alloc] initWithFrame:CGRectZero];
    self.view = root;
    UILabel *title = [[UILabel alloc] init];
    title.text = @"SunPad for Apple TV";
    title.font = [UIFont systemFontOfSize:52 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    self.titleLabel = title;
    UILabel *status = [[UILabel alloc] init];
    status.font = [UIFont systemFontOfSize:27 weight:UIFontWeightRegular];
    status.textColor = [UIColor colorWithWhite:1 alpha:0.78];
    status.textAlignment = NSTextAlignmentCenter;
    status.numberOfLines = 0;
    self.statusLabel = status;
    UIStackView *actions = [[UIStackView alloc] init];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.alignment = UIStackViewAlignmentCenter;
    actions.spacing = 28;
    self.actions = actions;
    UIStackView *content = [[UIStackView alloc]
        initWithArrangedSubviews:@[title, status, actions]];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 32;
    [root addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],
        [content.widthAnchor constraintLessThanOrEqualToAnchor:root.widthAnchor multiplier:0.78],
        [content.widthAnchor constraintGreaterThanOrEqualToConstant:700],
    ]];
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(void (^)(void))action {
    UIButtonConfiguration *configuration =
        [UIButtonConfiguration filledButtonConfiguration];
    configuration.title = title;
    configuration.baseBackgroundColor = UIColor.systemOrangeColor;
    configuration.baseForegroundColor = UIColor.whiteColor;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(20, 34, 20, 34);
    return [UIButton buttonWithConfiguration:configuration
        primaryAction:[UIAction actionWithHandler:^(__kindof UIAction *unused) {
            (void)unused;
            if (action != nil) action();
        }]];
}

- (void)showStatus:(NSString *)status buttons:(NSArray<UIButton *> *)buttons {
    self.titleLabel.hidden = NO;
    self.statusLabel.hidden = NO;
    self.actions.hidden = NO;
    self.statusLabel.text = status;
    self.statusLabel.accessibilityLabel = status;
    for (UIView *view in self.actions.arrangedSubviews) {
        [self.actions removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (UIButton *button in buttons)
        [self.actions addArrangedSubview:button];
    [self setNeedsFocusUpdate];
    [self updateFocusIfNeeded];
}

- (void)hideSetup {
    self.titleLabel.hidden = YES;
    self.statusLabel.hidden = YES;
    self.actions.hidden = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    SunPadTVActiveController = self;
    [self startControllerInput];
    [self attemptStart];
}

- (void)startControllerInput {
    if (!self.controllerInputActive) {
        self.controllerInputActive = YES;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(controllerChanged:)
                      name:GCControllerDidConnectNotification object:nil];
        [center addObserver:self selector:@selector(controllerChanged:)
                      name:GCControllerDidDisconnectNotification object:nil];
    }
    [self reconcileController];
}

- (void)controllerChanged:(NSNotification *)notification {
    (void)notification;
    [self reconcileController];
    if (self.coreHost == nil)
        [self attemptStart];
}

- (void)reconcileController {
    if (self.controller != nil &&
        [GCController.controllers indexOfObjectIdenticalTo:self.controller] != NSNotFound &&
        self.controller.extendedGamepad != nil) {
        [self updatePadSnapshot:
            SunPadTVInputStateFromGamepad(self.controller.extendedGamepad)];
        return;
    }
    [self teardownRumble];
    self.controller.extendedGamepad.valueChangedHandler = nil;
    self.controller.playerIndex = GCControllerPlayerIndexUnset;
    self.controller = nil;
    [self updatePadSnapshot:(SunPadInputState){0}];
    for (GCController *candidate in GCController.controllers) {
        if (candidate.extendedGamepad == nil)
            continue;
        self.controller = candidate;
        candidate.playerIndex = GCControllerPlayerIndex1;
        [self configureRumbleForController:candidate];
        SunPadLog(@"controller selected vendor=%@ haptics=%d",
                  candidate.vendorName ?: @"unknown", candidate.haptics != nil);
        __weak SunPadTVViewController *weakSelf = self;
        candidate.extendedGamepad.valueChangedHandler =
            ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
                (void)element;
                SunPadTVViewController *strongSelf = weakSelf;
                if (strongSelf != nil && strongSelf.controllerInputActive) {
                    [strongSelf updatePadSnapshot:
                        SunPadTVInputStateFromGamepad(gamepad)];
                }
            };
        [self updatePadSnapshot:
            SunPadTVInputStateFromGamepad(candidate.extendedGamepad)];
        break;
    }
}

- (void)updatePadSnapshot:(SunPadInputState)state {
    SunPadTVPadSnapshot snapshot =
        SunPadTVSnapshotFromInputState(state, _modernCStickHorizontal);
    std::lock_guard<std::mutex> lock(_padMutex);
    _padSnapshot = snapshot;
}

- (BOOL)readPadSnapshot:(void *)buffer size:(size_t)size {
    if (buffer == nullptr || size != sizeof(SunPadTVPadSnapshot))
        return NO;
    std::lock_guard<std::mutex> lock(_padMutex);
    std::memcpy(buffer, &_padSnapshot, sizeof(_padSnapshot));
    return YES;
}

- (void)configureRumbleForController:(GCController *)controller {
    _rumbleSupported.store(false);
    _rumbleRequested.store(false);
    dispatch_async(_hapticsQueue, ^{
        if (controller.haptics == nil)
            return;

        NSError *error = nil;
        CHHapticEngine *engine = [controller.haptics
            createEngineWithLocality:GCHapticsLocalityDefault];
        engine.playsHapticsOnly = YES;
        NSArray<CHHapticEventParameter *> *eventParameters = @[
            [[CHHapticEventParameter alloc]
                initWithParameterID:CHHapticEventParameterIDHapticIntensity
                             value:1.0f],
            [[CHHapticEventParameter alloc]
                initWithParameterID:CHHapticEventParameterIDHapticSharpness
                             value:0.1f],
        ];
        CHHapticEvent *event = [[CHHapticEvent alloc]
            initWithEventType:CHHapticEventTypeHapticContinuous
                   parameters:eventParameters
                 relativeTime:0.0
                     duration:GCHapticDurationInfinite];
        CHHapticDynamicParameter *silence = [[CHHapticDynamicParameter alloc]
            initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl
                         value:0.0f
                  relativeTime:0.0];
        CHHapticPattern *pattern = [[CHHapticPattern alloc]
            initWithEvents:@[event] parameters:@[silence] error:&error];
        id<CHHapticAdvancedPatternPlayer> player = pattern == nil
            ? nil
            : [engine createAdvancedPlayerWithPattern:pattern error:&error];
        if (engine == nil || player == nil ||
            ![engine startAndReturnError:&error] ||
            ![player startAtTime:CHHapticTimeImmediate error:&error]) {
            SunPadLog(@"controller haptics unavailable error=%@",
                      error.localizedDescription ?: @"unknown");
            return;
        }

        __weak SunPadTVViewController *weakSelf = self;
        __weak CHHapticEngine *weakEngine = engine;
        engine.stoppedHandler = ^(CHHapticEngineStoppedReason reason) {
            SunPadTVViewController *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            dispatch_async(strongSelf->_hapticsQueue, ^{
                if (strongSelf->_hapticEngine == weakEngine) {
                    strongSelf->_rumbleSupported.store(false);
                    SunPadLog(@"controller haptics stopped reason=%ld",
                              (long)reason);
                }
            });
        };
        _hapticEngine = engine;
        _rumblePlayer = player;
        _rumbleSupported.store(true);
        SunPadLog(@"controller haptics ready");
    });
}

- (void)teardownRumble {
    _rumbleSupported.store(false);
    _rumbleRequested.store(false);
    if (_hapticsQueue == nil)
        return;
    __weak SunPadTVViewController *weakSelf = self;
    dispatch_async(_hapticsQueue, ^{
        SunPadTVViewController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        strongSelf->_hapticEngine.stoppedHandler =
            ^(CHHapticEngineStoppedReason reason) { (void)reason; };
        [strongSelf->_rumblePlayer stopAtTime:CHHapticTimeImmediate error:nil];
        [strongSelf->_hapticEngine stopWithCompletionHandler:nil];
        strongSelf->_rumblePlayer = nil;
        strongSelf->_hapticEngine = nil;
    });
}

- (BOOL)setRumbleEnabled:(BOOL)enabled {
    if (!_rumbleSupported.load())
        return NO;
    if (_rumbleRequested.exchange(enabled) == enabled)
        return YES;
    dispatch_async(_hapticsQueue, ^{
        CHHapticDynamicParameter *intensity = [[CHHapticDynamicParameter alloc]
            initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl
                         value:enabled ? 1.0f : 0.0f
                  relativeTime:0.0];
        NSError *error = nil;
        if (![self->_rumblePlayer sendParameters:@[intensity]
                                          atTime:CHHapticTimeImmediate
                                           error:&error]) {
            self->_rumbleSupported.store(false);
            SunPadLog(@"controller rumble failed error=%@",
                      error.localizedDescription ?: @"unknown");
        } else if (enabled && !self->_rumbleBridgeLogged.exchange(true)) {
            SunPadLog(@"controller rumble bridge active");
        }
    });
    return YES;
}

- (void)attemptStart {
    if (self.coreHost != nil)
        return;
    NSError *validationError = nil;
    NSString *problem = SunPadTVValidateGameData(&validationError);
    __weak SunPadTVViewController *weakSelf = self;
    if (problem != nil || validationError != nil) {
        UIButton *retry = [self buttonWithTitle:@"Retry" action:^{
            [weakSelf attemptStart];
        }];
        [self showStatus:[NSString stringWithFormat:
            @"Game data is not included. Stage your own validated GMSE01 folder from a Mac, then choose Retry.\n\n%@",
            problem ?: validationError.localizedDescription] buttons:@[retry]];
        return;
    }
    NSString *modulePath = [NSBundle.mainBundle.bundlePath
        stringByAppendingPathComponent:@"gGMSE01_recomp.dylib"];
    if (![NSFileManager.defaultManager isReadableFileAtPath:modulePath]) {
        [self showStatus:@"The tvOS GMSE01 module is missing from this build."
                 buttons:@[]];
        return;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:SunPadTVSupportRoot()
        withIntermediateDirectories:YES attributes:nil error:nil];
    SunPadSettings *settings = SunPadSettings.sharedSettings;
    settings.renderScale = 1;
    settings.aspectRatioMode = SunPadAspectRatioOriginal;
    settings.experimental60FPS = NO;
    settings.experimentalPerformanceMode = NO;
    [settings synchronize];
    SunPadDiagnosticsStart();
    [self hideSetup];
    SunPadCoreHost *host = [[SunPadCoreHost alloc]
        initWithLayer:(CAMetalLayer *)self.view.layer];
    self.coreHost = host;
    [host startWithGameRoot:SunPadTVGameRoot() discImagePath:@""
                 modulePath:modulePath userDirectory:SunPadTVSupportRoot()
                     onError:^(NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SunPadTVViewController *strongSelf = weakSelf;
            [strongSelf stopRuntime];
            UIButton *retry = [strongSelf buttonWithTitle:@"Retry" action:^{
                [weakSelf attemptStart];
            }];
            [strongSelf showStatus:[NSString stringWithFormat:
                @"SunPad could not start.\n\n%@", message] buttons:@[retry]];
        });
    }];
}

- (void)pauseRuntime {
    self.controllerInputActive = NO;
    [self updatePadSnapshot:(SunPadInputState){0}];
    [self setRumbleEnabled:NO];
    [self.coreHost pauseRuntimeForSystemEvent];
}

- (void)resumeRuntime {
    self.controllerInputActive = YES;
    [self reconcileController];
    [self.coreHost resumeRuntimeAfterSystemEvent];
    if (self.coreHost == nil)
        [self attemptStart];
}

- (void)stopRuntime {
    [self setRumbleEnabled:NO];
    [self.coreHost stop];
    self.coreHost = nil;
    [self updatePadSnapshot:(SunPadInputState){0}];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    self.controller.extendedGamepad.valueChangedHandler = nil;
    if (SunPadTVActiveController == self)
        SunPadTVActiveController = nil;
    [self teardownRumble];
    [self stopRuntime];
}

@end

@interface SunPadTVSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation SunPadTVSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
                                      options:(UISceneConnectionOptions *)options {
    (void)session;
    (void)options;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[SunPadTVViewController alloc] init];
    [self.window makeKeyAndVisible];
}
- (SunPadTVViewController *)controller {
    return (SunPadTVViewController *)self.window.rootViewController;
}
- (void)sceneWillResignActive:(UIScene *)scene { (void)scene; [self.controller pauseRuntime]; }
- (void)sceneDidEnterBackground:(UIScene *)scene { (void)scene; [self.controller pauseRuntime]; }
- (void)sceneDidBecomeActive:(UIScene *)scene { (void)scene; [self.controller resumeRuntime]; }
- (void)sceneDidDisconnect:(UIScene *)scene { (void)scene; [self.controller stopRuntime]; }
@end

@interface SunPadTVAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation SunPadTVAppDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;
    (void)options;
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass(SunPadTVAppDelegate.class));
    }
}
