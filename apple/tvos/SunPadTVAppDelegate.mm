#import <CommonCrypto/CommonDigest.h>
#import <GameController/GameController.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#import "SunPadControllerMapping.h"
#import "SunPadCoreHost.h"
#import "SunPadDiagnostics.h"
#import "SunPadInputMixer.h"
#import "SunPadSettings.h"

#include <cmath>
#include <cstring>

namespace {

NSString *const SunPadTVMainDOLSHA256 =
    @"13934c863d649b1ddca1ca4d7748f49d28a571685cbee5fb1542545c32869955";

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

BOOL SunPadTVHasExtendedController(void) {
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil)
            return YES;
    }
    return NO;
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

@interface SunPadTVViewController : UIViewController
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIStackView *actions;
@property(nonatomic, strong) SunPadCoreHost *coreHost;
@property(nonatomic, strong) GCController *controller;
@property(nonatomic, strong) dispatch_source_t inputTimer;
@property(nonatomic, assign) BOOL controllerInputActive;
- (void)attemptStart;
- (void)pauseRuntime;
- (void)resumeRuntime;
- (void)stopRuntime;
@end

@implementation SunPadTVViewController

- (void)loadView {
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
    if (self.inputTimer == nil) {
        dispatch_source_t timer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0),
                                  NSEC_PER_SEC / 60, NSEC_PER_MSEC);
        __weak SunPadTVViewController *weakSelf = self;
        dispatch_source_set_event_handler(timer, ^{
            SunPadTVViewController *strongSelf = weakSelf;
            if (strongSelf.coreHost != nil) {
                [strongSelf.coreHost publishInput:
                    [SunPadInputMixer.sharedMixer consumeMergedState]];
            }
        });
        dispatch_resume(timer);
        self.inputTimer = timer;
    }
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
        [SunPadInputMixer.sharedMixer
            setInputState:SunPadTVInputStateFromGamepad(self.controller.extendedGamepad)
                 fromTouch:NO];
        return;
    }
    self.controller.extendedGamepad.valueChangedHandler = nil;
    self.controller.playerIndex = GCControllerPlayerIndexUnset;
    self.controller = nil;
    [SunPadInputMixer.sharedMixer clearInputFromTouch:NO];
    for (GCController *candidate in GCController.controllers) {
        if (candidate.extendedGamepad == nil)
            continue;
        self.controller = candidate;
        candidate.playerIndex = GCControllerPlayerIndex1;
        __weak SunPadTVViewController *weakSelf = self;
        candidate.extendedGamepad.valueChangedHandler =
            ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
                (void)element;
                SunPadTVViewController *strongSelf = weakSelf;
                if (strongSelf != nil && strongSelf.controllerInputActive) {
                    [SunPadInputMixer.sharedMixer
                        setInputState:SunPadTVInputStateFromGamepad(gamepad)
                             fromTouch:NO];
                }
            };
        [SunPadInputMixer.sharedMixer
            setInputState:SunPadTVInputStateFromGamepad(candidate.extendedGamepad)
                 fromTouch:NO];
        break;
    }
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
    [self reconcileController];
    if (!SunPadTVHasExtendedController()) {
        UIButton *find = [self buttonWithTitle:@"Find Controller" action:^{
            [GCController startWirelessControllerDiscoveryWithCompletionHandler:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf reconcileController];
                    [weakSelf attemptStart];
                });
            }];
        }];
        [self showStatus:
            @"Connect an Extended Gamepad in Apple TV Settings. The Siri Remote operates this setup screen but is not a gameplay controller."
                 buttons:@[find]];
        return;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:SunPadTVSupportRoot()
        withIntermediateDirectories:YES attributes:nil error:nil];
    SunPadSettings *settings = SunPadSettings.sharedSettings;
    settings.renderScale = 1;
    settings.aspectRatioMode = SunPadAspectRatioWidescreen;
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
    [SunPadInputMixer.sharedMixer clearInputFromTouch:NO];
    [self.coreHost publishInput:(SunPadInputState){0}];
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
    [self.coreHost stop];
    self.coreHost = nil;
    [SunPadInputMixer.sharedMixer clearInputFromTouch:NO];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (self.inputTimer != nil)
        dispatch_source_cancel(self.inputTimer);
    self.controller.extendedGamepad.valueChangedHandler = nil;
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
