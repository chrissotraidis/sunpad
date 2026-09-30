#import "SunPadGameViewController.h"

#import "SunPadCoreHost.h"
#import "SunPadControllerMapping.h"
#import "SunPadControllerSlots.h"
#import "SunPadDiagnostics.h"
#import "SunPadDiscExtractor.h"
#import "SunPadGameOverlay.h"
#import "SunPadInputMixer.h"
#import "SunPadSettings.h"

#import <CommonCrypto/CommonDigest.h>
#import <GameController/GameController.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <TargetConditionals.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <mach/mach.h>
#include <pthread.h>
#include <sys/resource.h>
#include <algorithm>
#include <cmath>
#include <unordered_map>
#include <vector>

static constexpr CGFloat SunPadDrawableScale = 1.0;
static NSString *const SunPadSupportedImageSHA256 =
    @"67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d";

static uintptr_t SunPadControllerInstanceID(GCController *controller) {
    return reinterpret_cast<uintptr_t>((__bridge void *)controller);
}

static NSString *SunPadControllerInstanceName(uintptr_t instance) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)instance];
}

static GCControllerPlayerIndex SunPadPlayerIndexForSlot(NSInteger slot) {
    switch (slot) {
    case 0: return GCControllerPlayerIndex1;
    case 1: return GCControllerPlayerIndex2;
    case 2: return GCControllerPlayerIndex3;
    case 3: return GCControllerPlayerIndex4;
    default: return GCControllerPlayerIndexUnset;
    }
}

static NSString *SunPadThermalStateName(NSProcessInfoThermalState state) {
    switch (state) {
    case NSProcessInfoThermalStateFair: return @"fair";
    case NSProcessInfoThermalStateSerious: return @"serious";
    case NSProcessInfoThermalStateCritical: return @"critical";
    case NSProcessInfoThermalStateNominal:
    default: return @"nominal";
    }
}

static BOOL SunPadProcessUsage(double *cpuSeconds, double *residentMiB) {
    struct rusage usage = {};
    if (getrusage(RUSAGE_SELF, &usage) != 0)
        return NO;

    mach_task_basic_info_data_t info = {};
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                                     reinterpret_cast<task_info_t>(&info), &count);
    if (result != KERN_SUCCESS)
        return NO;

    *cpuSeconds = (double)usage.ru_utime.tv_sec + (double)usage.ru_utime.tv_usec / 1e6 +
                  (double)usage.ru_stime.tv_sec + (double)usage.ru_stime.tv_usec / 1e6;
    *residentMiB = (double)info.resident_size / (1024.0 * 1024.0);
    return YES;
}

static NSString *SunPadTopThreadUsage(NSTimeInterval elapsed) {
    static std::unordered_map<uint64_t, double> previousCPUSeconds;
    if (elapsed <= 0.0)
        return @"unavailable";

    thread_act_array_t threads = nullptr;
    mach_msg_type_number_t threadCount = 0;
    if (task_threads(mach_task_self(), &threads, &threadCount) != KERN_SUCCESS)
        return @"unavailable";

    struct ThreadSample {
        double percent;
        std::string name;
    };
    std::vector<ThreadSample> samples;
    std::unordered_map<uint64_t, double> currentCPUSeconds;
    for (mach_msg_type_number_t index = 0; index < threadCount; ++index) {
        thread_identifier_info_data_t identifier = {};
        mach_msg_type_number_t identifierCount = THREAD_IDENTIFIER_INFO_COUNT;
        thread_basic_info_data_t basic = {};
        mach_msg_type_number_t basicCount = THREAD_BASIC_INFO_COUNT;
        if (thread_info(threads[index], THREAD_IDENTIFIER_INFO,
                        reinterpret_cast<thread_info_t>(&identifier), &identifierCount) == KERN_SUCCESS &&
            thread_info(threads[index], THREAD_BASIC_INFO,
                        reinterpret_cast<thread_info_t>(&basic), &basicCount) == KERN_SUCCESS) {
            double total = basic.user_time.seconds + basic.user_time.microseconds / 1e6 +
                           basic.system_time.seconds + basic.system_time.microseconds / 1e6;
            currentCPUSeconds[identifier.thread_id] = total;
            auto previous = previousCPUSeconds.find(identifier.thread_id);
            if (previous != previousCPUSeconds.end() && total >= previous->second) {
                char threadName[64] = {};
                pthread_t pthread = pthread_from_mach_thread_np(threads[index]);
                if (pthread != nullptr)
                    pthread_getname_np(pthread, threadName, sizeof(threadName));
                std::string name = threadName[0] != '\0' ? threadName : "unnamed";
                samples.push_back({100.0 * (total - previous->second) / elapsed,
                                   std::move(name)});
            }
        }
        mach_port_deallocate(mach_task_self(), threads[index]);
    }
    vm_deallocate(mach_task_self(), reinterpret_cast<vm_address_t>(threads),
                  threadCount * sizeof(thread_t));
    previousCPUSeconds = std::move(currentCPUSeconds);

    std::sort(samples.begin(), samples.end(), [](const ThreadSample& left,
                                                  const ThreadSample& right) {
        return left.percent > right.percent;
    });
    NSMutableArray<NSString *> *top = [NSMutableArray array];
    for (std::size_t index = 0; index < std::min<std::size_t>(samples.size(), 3); ++index) {
        [top addObject:[NSString stringWithFormat:@"%s:%.1f",
            samples[index].name.c_str(), samples[index].percent]];
    }
    return top.count > 0 ? [top componentsJoinedByString:@","] : @"baseline";
}

static SunPadPhysicalControllerButton SunPadPressedFaceButtons(GCExtendedGamepad *pad) {
    uint8_t buttons = 0;
    if (pad.buttonA.isPressed) buttons |= SunPadPhysicalControllerButtonA;
    if (pad.buttonB.isPressed) buttons |= SunPadPhysicalControllerButtonB;
    if (pad.buttonX.isPressed) buttons |= SunPadPhysicalControllerButtonX;
    if (pad.buttonY.isPressed) buttons |= SunPadPhysicalControllerButtonY;
    if (pad.leftShoulder.isPressed) buttons |= SunPadPhysicalControllerButtonLeftShoulder;
    return (SunPadPhysicalControllerButton)buttons;
}

static NSString *SunPadGameButtonName(uint16_t gameButton) {
    switch (gameButton) {
    case SunPadButtonA: return @"GameCube A";
    case SunPadButtonB: return @"GameCube B";
    case SunPadButtonX: return @"GameCube X";
    case SunPadButtonY: return @"GameCube Y";
    case SunPadButtonZ: return @"GameCube Z";
    default: return @"Unknown";
    }
}

static SunPadPhysicalControllerButton SunPadMappedPhysicalButton(
    SunPadControllerButtonMapping mapping, uint16_t gameButton) {
    switch (gameButton) {
    case SunPadButtonA: return mapping.gameA;
    case SunPadButtonB: return mapping.gameB;
    case SunPadButtonX: return mapping.gameX;
    case SunPadButtonY: return mapping.gameY;
    case SunPadButtonZ: return mapping.gameZ;
    default: return (SunPadPhysicalControllerButton)0;
    }
}

static NSString *_Nullable SunPadSHA256ForFile(NSString *path, NSError **error) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (handle == nil) {
        if (error != nil) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadNoSuchFileError
                                     userInfo:@{NSFilePathErrorKey: path}];
        }
        return nil;
    }

    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    while (true) {
        NSError *readError = nil;
        NSData *data = [handle readDataUpToLength:4 * 1024 * 1024 error:&readError];
        if (data == nil || readError != nil) {
            [handle closeFile];
            if (error != nil)
                *error = readError;
            return nil;
        }
        if (data.length == 0)
            break;
        CC_SHA256_Update(&context, data.bytes, (CC_LONG)data.length);
    }
    [handle closeFile];

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (unsigned char byte : digest)
        [hex appendFormat:@"%02x", byte];
    return hex;
}

static NSUInteger SunPadRegularFileCount(NSString *directory) {
    NSDirectoryEnumerator<NSString *> *enumerator =
        [[NSFileManager defaultManager] enumeratorAtPath:directory];
    NSUInteger count = 0;
    for (NSString *relative in enumerator) {
        BOOL isDirectory = NO;
        [[NSFileManager defaultManager]
            fileExistsAtPath:[directory stringByAppendingPathComponent:relative]
                 isDirectory:&isDirectory];
        if (!isDirectory)
            ++count;
    }
    return count;
}

/* UIView whose backing layer is a CAMetalLayer: the ModernGekko Metal video
 * backend renders directly into this layer (Dolphin owns the drawable). */
@interface SunPadMetalSurfaceView : UIView
+ (Class)layerClass;
@end

@implementation SunPadMetalSurfaceView
+ (Class)layerClass {
    return [CAMetalLayer class];
}
@end

@interface SunPadGameViewController () <SunPadGameOverlayDelegate, UIDocumentPickerDelegate>
- (void)configureController:(GCController *)controller playerSlot:(NSInteger)slot;
- (nullable GCController *)controllerForPlayerSlot:(NSInteger)slot;
- (NSArray<NSURL *> *)gameImagesInDocumentsDirectory;
- (NSString *)modulePathFromConfiguration:(NSDictionary *)configuration;
- (void)presentGameDataImport;
- (void)presentGameDataFolderImport;
- (void)publishInputFromController:(GCController *)controller
                           gamepad:(GCExtendedGamepad *)gamepad;
- (void)reconcileControllersForReason:(NSString *)reason;
- (void)restoreOverlayAfterForeground;
- (NSString *)resolvedImportTestPath:(NSString *)requestedPath;
- (void)showGameDataSetupState;
- (NSString *)sunPadSupportRoot;
@end

@implementation SunPadGameViewController {
    SunPadMetalSurfaceView *_gameView;
    SunPadCoreHost *_coreHost;
    SunPadGameOverlay *_overlay;
    dispatch_source_t _controllerTimer;
    UILabel *_fpsLabel;
    UILabel *_bootStatusLabel;
    UIActivityIndicatorView *_bootActivityIndicator;
    UIButton *_gameDataImportButton;
    SunPadControllerSlots _controllerSlots;
    NSMutableDictionary<NSNumber *, GCController *> *_configuredControllers;
    CGSize _lastLoggedDrawableSize;
    NSUInteger _performanceLogSeconds;
    double _lastPerformanceCPUSeconds;
    NSTimeInterval _lastPerformanceUptime;
    BOOL _hasPerformanceUsageBaseline;
    NSString *_lastPerformanceSummary;
    NSDate *_lastScreenshotMarker;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    // Super Mario Sunshine is a landscape game; the overlay is designed for
    // landscape like the BellPad reference (never portrait).
    return UIInterfaceOrientationMaskLandscape;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    SunPadLog(@"viewDidLoad bounds=%@ orientation=%ld",
              NSStringFromCGRect(self.view.bounds), (long)UIDevice.currentDevice.orientation);
    SunPadLog(@"game mode eligibility declared=%d",
              [[NSBundle.mainBundle objectForInfoDictionaryKey:@"LSSupportsGameMode"] boolValue]);
    self.view.backgroundColor = UIColor.blackColor;

    _gameView = [[SunPadMetalSurfaceView alloc] initWithFrame:self.view.bounds];
    _gameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_gameView];

    CAMetalLayer *layer = (CAMetalLayer *)_gameView.layer;
    layer.device = MTLCreateSystemDefaultDevice();
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    layer.drawableSize = CGSizeMake(CGRectGetWidth(_gameView.bounds) * SunPadDrawableScale,
                                    CGRectGetHeight(_gameView.bounds) * SunPadDrawableScale);

    _overlay = [[SunPadGameOverlay alloc] initWithFrame:self.view.bounds];
    _overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _overlay.delegate = self;
    [self.view addSubview:_overlay];

    _bootActivityIndicator = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _bootActivityIndicator.color = UIColor.whiteColor;
    _bootActivityIndicator.hidesWhenStopped = YES;
    [_bootActivityIndicator startAnimating];
    [self.view addSubview:_bootActivityIndicator];

    _bootStatusLabel = [UILabel new];
    _bootStatusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    _bootStatusLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
    _bootStatusLabel.textAlignment = NSTextAlignmentCenter;
    _bootStatusLabel.numberOfLines = 0;
    _bootStatusLabel.text = @"Preparing runtime…";
    _bootStatusLabel.accessibilityLabel = @"Preparing runtime";
    [self.view addSubview:_bootStatusLabel];

    _gameDataImportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *importConfiguration =
        [UIButtonConfiguration filledButtonConfiguration];
    importConfiguration.title = @"Choose ISO or GCM";
    importConfiguration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    importConfiguration.baseBackgroundColor = UIColor.systemBlueColor;
    importConfiguration.baseForegroundColor = UIColor.whiteColor;
    importConfiguration.contentInsets = NSDirectionalEdgeInsetsMake(14.0, 24.0, 14.0, 24.0);
    _gameDataImportButton.configuration = importConfiguration;
    _gameDataImportButton.accessibilityHint =
        @"Opens Files to select supported Super Mario Sunshine game data.";
    [_gameDataImportButton addTarget:self
                              action:@selector(presentGameDataImport)
                    forControlEvents:UIControlEventTouchUpInside];
    _gameDataImportButton.hidden = YES;
    [self.view addSubview:_gameDataImportButton];

    _configuredControllers = [NSMutableDictionary dictionary];

    _fpsLabel = [UILabel new];
    _fpsLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    _fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0
                                                      weight:UIFontWeightSemibold];
    _fpsLabel.text = @"";
    _fpsLabel.hidden = YES;
    [self.view addSubview:_fpsLabel];
    [self startFPSMonitor];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsChanged:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userDidTakeScreenshot:)
                                                 name:UIApplicationUserDidTakeScreenshotNotification
                                               object:nil];
    // SunPad is an app-delegate UIKit app rather than a scene-based app. These
    // legacy notifications remain the only direct external-screen signal for
    // this deployment model on iPadOS 16+.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(displayConfigurationChanged:)
                                                 name:UIScreenDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(displayConfigurationChanged:)
                                                 name:UIScreenDidDisconnectNotification
                                               object:nil];
#pragma clang diagnostic pop
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(displayConfigurationChanged:)
                                                 name:UIScreenModeDidChangeNotification
                                               object:nil];
    // DEBUG hook: -sunpadImportTest <iso path> runs the full import flow.
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    NSUInteger importIndex = [arguments indexOfObject:@"-sunpadImportTest"];
    if (importIndex != NSNotFound && importIndex + 1 < arguments.count) {
        NSString *imagePath = [self resolvedImportTestPath:arguments[importIndex + 1]];
        NSLog(@"[SunPad] import test requested=%@ resolved=%@", arguments[importIndex + 1], imagePath);
        [self startInputConsumer];
        [self observeControllers];
        [self importGameDataFromURL:[NSURL fileURLWithPath:imagePath]];
        return;
    }
    [self startGameIfProvisioned];
    [self startInputConsumer];
    [self observeControllers];
}

// Physical-device launches cannot refer to the host's /tmp. devicectl copies
// into the app data container, whose actual temporary directory is returned by
// NSTemporaryDirectory(). Keep the command-line hook usable for both the
// Simulator's host path and the device's injected ISO.
- (NSString *)resolvedImportTestPath:(NSString *)requestedPath {
    if ([[NSFileManager defaultManager] fileExistsAtPath:requestedPath])
        return requestedPath;
    NSString *prefix = @"/tmp/";
    if ([requestedPath hasPrefix:prefix]) {
        NSString *relativePath = [requestedPath substringFromIndex:prefix.length];
        NSString *sandboxPath = [NSTemporaryDirectory() stringByAppendingPathComponent:relativePath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:sandboxPath])
            return sandboxPath;
    }
    return requestedPath;
}

- (NSString *)modulePathFromConfiguration:(NSDictionary *)configuration {
    NSString *hostPath = configuration[@"DevModulePath"];
    if (hostPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:hostPath])
        return hostPath;

    NSString *deviceRelativePath = configuration[@"DeviceModuleRelativePath"];
#if !TARGET_OS_SIMULATOR
    // Simulator and device provisioning share a generated development plist.
    // A Simulator build may therefore leave DevModulePath pointing at the Mac.
    // Device installs always use this stable, sandbox-relative module name.
    if (deviceRelativePath.length == 0)
        deviceRelativePath = @"gGMSE01_recomp.dylib";
#endif
    if (deviceRelativePath.length > 0) {
        NSString *temporaryPath =
            [NSTemporaryDirectory() stringByAppendingPathComponent:deviceRelativePath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:temporaryPath])
            return temporaryPath;

        // Local device builds can carry the signed, user-generated module in
        // the app bundle when CoreDevice temporary-file uploads are unavailable.
        NSString *bundledPath =
            [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:deviceRelativePath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:bundledPath])
            return bundledPath;
        return temporaryPath;
    }
    return hostPath;
}

- (void)startFPSMonitor {
    static dispatch_source_t fpsTimer;
    if (fpsTimer)
        return;
    fpsTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                      dispatch_get_main_queue());
    dispatch_source_set_timer(fpsTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              1.0 * NSEC_PER_SEC, 0);
    __weak SunPadGameViewController *weakSelf = self;
    dispatch_source_set_event_handler(fpsTimer, ^{
        [weakSelf updateFPSLabel];
    });
    dispatch_resume(fpsTimer);
}

- (void)updateFPSLabel {
    [self reconcileControllersForReason:@"periodic"];
    BOOL applicationActive = UIApplication.sharedApplication.applicationState ==
        UIApplicationStateActive;
    double fps = applicationActive ? [_coreHost currentFPS] : 0.0;
    if (!applicationActive) {
        _performanceLogSeconds = 0;
        _hasPerformanceUsageBaseline = NO;
    }
    if (fps > 0.0) {
        _bootStatusLabel.hidden = YES;
        [_bootActivityIndicator stopAnimating];
        if (++_performanceLogSeconds >= 10) {
            _performanceLogSeconds = 0;
            NSProcessInfo *processInfo = NSProcessInfo.processInfo;
            double cpuSeconds = 0.0;
            double residentMiB = 0.0;
            NSTimeInterval uptime = processInfo.systemUptime;
            BOOL hasUsage = SunPadProcessUsage(&cpuSeconds, &residentMiB);
            double appCPUPercent = -1.0;
            NSTimeInterval usageInterval = 0.0;
            if (hasUsage && _hasPerformanceUsageBaseline &&
                uptime > _lastPerformanceUptime) {
                usageInterval = uptime - _lastPerformanceUptime;
                appCPUPercent = 100.0 * (cpuSeconds - _lastPerformanceCPUSeconds) /
                                usageInterval;
            }
            if (hasUsage) {
                _lastPerformanceCPUSeconds = cpuSeconds;
                _lastPerformanceUptime = uptime;
                _hasPerformanceUsageBaseline = YES;
            }
            NSString *topThreads = SunPadTopThreadUsage(usageInterval);
            _lastPerformanceSummary = [NSString stringWithFormat:
                @"fps=%.1f vps=%.1f speedRatio=%.3f efb=%@ renderScale=%ld aspect=%ld "
                 @"thermal=%@ lowPower=%d appCPU=%.1f residentMiB=%.1f topThreads=%@",
                      fps, [_coreHost currentVPS], [_coreHost currentSpeed],
                      [_coreHost efbResolution],
                      (long)[_coreHost currentRenderScale],
                      (long)[SunPadSettings sharedSettings].aspectRatioMode,
                      SunPadThermalStateName(processInfo.thermalState),
                      processInfo.isLowPowerModeEnabled, appCPUPercent, residentMiB,
                      topThreads];
            NSString *graphics = [[_coreHost diagnosticSummary]
                stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            SunPadLog(@"performance %@ %@", _lastPerformanceSummary, graphics);
        }
    } else if (_coreHost != nil && !_bootStatusLabel.hidden &&
               _bootActivityIndicator.isAnimating) {
        _performanceLogSeconds = 0;
        _bootStatusLabel.text = @"Waiting for first frame…";
        _bootStatusLabel.accessibilityLabel = @"Waiting for first frame";
    }

    if (![SunPadSettings sharedSettings].showFPSCounter) {
        _fpsLabel.hidden = YES;
        return;
    }
    if (fps > 0.0) {
        // Super Mario Sunshine's supported mode runs at a 30 Hz NTSC frame
        // rate, so FPS near 30 is full frame rate. Speed and VPS are retained
        // in the diagnostic telemetry rather than cluttering this overlay.
        _fpsLabel.text = [NSString stringWithFormat:@"%.1f FPS", fps];
        _fpsLabel.hidden = NO;
        NSLog(@"[SunPad] FPS: %.1f  EFB: %@", fps, [_coreHost efbResolution]);
    } else {
        _fpsLabel.hidden = YES;
    }
}

- (void)userDidTakeScreenshot:(NSNotification *)notification {
    (void)notification;
    _lastScreenshotMarker = NSDate.date;
    NSString *context = [[self gameOverlayDiagnosticContext:_overlay]
        stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    SunPadLog(@"diagnostic marker reason=user-screenshot %@", context);
}

- (void)observeControllers {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerDidConnect:)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerDidDisconnect:)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];
    [self reconcileControllersForReason:@"launch"];
}

- (void)controllerDidConnect:(NSNotification *)notification {
    GCController *controller = notification.object;
    uintptr_t instance = SunPadControllerInstanceID(controller);
    SunPadLog(@"controller connected instance=%@ vendor=%@ category=%@ extended=%d count=%lu",
              SunPadControllerInstanceName(instance),
              controller.vendorName ?: @"unknown", controller.productCategory ?: @"unknown",
              controller.extendedGamepad != nil, (unsigned long)GCController.controllers.count);
    [self reconcileControllersForReason:@"connect"];
}

- (void)controllerDidDisconnect:(NSNotification *)notification {
    GCController *controller = notification.object;
    uintptr_t instance = SunPadControllerInstanceID(controller);
    NSInteger slot = _controllerSlots.SlotFor(instance);
    SunPadLog(@"controller disconnected instance=%@ slot=%ld vendor=%@ count=%lu",
              SunPadControllerInstanceName(instance), (long)(slot >= 0 ? slot + 1 : 0),
              controller.vendorName ?: @"unknown", (unsigned long)GCController.controllers.count);
    [self reconcileControllersForReason:@"disconnect"];
}

/* Analog triggers carry L/R pressure (FLUDD), the left shoulder is Z,
 * the right shoulder is medium analog R, menu is Start, and the D-pad maps
 * to D-pad bits. */
- (void)configureController:(GCController *)controller playerSlot:(NSInteger)slot {
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    if (gamepad == nil) {
        SunPadLog(@"controller ignored instance=%@ vendor=%@ reason=no extended gamepad profile",
                  SunPadControllerInstanceName(SunPadControllerInstanceID(controller)),
                  controller.vendorName ?: @"unknown");
        return;
    }
    SunPadLog(@"controller configured instance=%@ slot=%ld vendor=%@ category=%@",
              SunPadControllerInstanceName(SunPadControllerInstanceID(controller)),
              (long)(slot + 1), controller.vendorName ?: @"unknown",
              controller.productCategory ?: @"unknown");
    __weak SunPadGameViewController *weakSelf = self;
    __weak GCController *weakController = controller;
    gamepad.valueChangedHandler = ^(GCExtendedGamepad *pad, GCControllerElement *element) {
        (void)element;
        dispatch_async(dispatch_get_main_queue(), ^{
            SunPadGameViewController *strongSelf = weakSelf;
            GCController *strongController = weakController;
            if (strongSelf != nil && strongController != nil)
                [strongSelf publishInputFromController:strongController gamepad:pad];
        });
    };
    [self publishInputFromController:controller gamepad:gamepad];
}

- (void)publishInputFromController:(GCController *)controller
                           gamepad:(GCExtendedGamepad *)gamepad {
    NSArray<GCController *> *currentControllers = GCController.controllers;
    if ([currentControllers indexOfObjectIdenticalTo:controller] == NSNotFound) {
        uintptr_t instance = SunPadControllerInstanceID(controller);
        SunPadLog(@"controller stale callback instance=%@ slot=%ld action=reconcile",
                  SunPadControllerInstanceName(instance),
                  (long)(_controllerSlots.SlotFor(instance) + 1));
        [self reconcileControllersForReason:@"stale-callback"];
        return;
    }

    uintptr_t instance = SunPadControllerInstanceID(controller);
    if (_controllerSlots.SlotFor(instance) != 0)
        return;

    // Every callback is a complete snapshot. Leaving buttons uninitialized
    // made random button edges overflow the old fixed-size pipe buffer.
    SunPadInputState state = {};
    state.connected = 1;
    state.buttons |= SunPadApplyControllerButtonMapping(
        [SunPadControllerMappingStore mapping], SunPadPressedFaceButtons(gamepad));
    if (gamepad.buttonMenu.isPressed) state.buttons |= SunPadButtonStart;
    if (gamepad.dpad.up.isPressed) state.buttons |= SunPadButtonDpadUp;
    if (gamepad.dpad.down.isPressed) state.buttons |= SunPadButtonDpadDown;
    if (gamepad.dpad.left.isPressed) state.buttons |= SunPadButtonDpadLeft;
    if (gamepad.dpad.right.isPressed) state.buttons |= SunPadButtonDpadRight;
    state.stickX = (int8_t)std::lround(gamepad.leftThumbstick.xAxis.value * 127.0f);
    state.stickY = (int8_t)std::lround(gamepad.leftThumbstick.yAxis.value * 127.0f);
    state.cStickX = (int8_t)std::lround(gamepad.rightThumbstick.xAxis.value * 127.0f);
    state.cStickY = (int8_t)std::lround(gamepad.rightThumbstick.yAxis.value * 127.0f);
    state.triggerL = (uint8_t)std::lround(gamepad.leftTrigger.value * 255.0f);
    uint8_t physicalTriggerR =
        (uint8_t)std::lround(gamepad.rightTrigger.value * 255.0f);
    state.triggerR = SunPadControllerRightTriggerPressure(
        physicalTriggerR, gamepad.rightShoulder.isPressed);
    if (state.triggerL > 30) state.buttons |= SunPadButtonL;
    if (physicalTriggerR > 30) state.buttons |= SunPadButtonR;
    [[SunPadInputMixer sharedMixer] setInputState:state fromTouch:NO];
}

- (void)reconcileControllersForReason:(NSString *)reason {
    NSArray<GCController *> *currentControllers = GCController.controllers;
    std::vector<uintptr_t> currentInstances;
    for (GCController *controller in currentControllers) {
        if (controller.extendedGamepad != nil)
            currentInstances.push_back(SunPadControllerInstanceID(controller));
    }

    SunPadControllerReconcileResult result = _controllerSlots.Reconcile(currentInstances);
    for (const SunPadControllerSlotChange &change : result.removed) {
        NSNumber *key = @(change.instance);
        GCController *staleController = _configuredControllers[key];
        staleController.extendedGamepad.valueChangedHandler = nil;
        staleController.playerIndex = GCControllerPlayerIndexUnset;
        [_configuredControllers removeObjectForKey:key];
        if (change.slot == 0)
            [[SunPadInputMixer sharedMixer] clearInputFromTouch:NO];
        SunPadLog(@"controller reconciled reason=%@ instance=%@ slot=%ld status=%@",
                  reason, SunPadControllerInstanceName(change.instance),
                  (long)(change.slot + 1), @"removed");
    }

    if (!result.removed.empty() || !result.assigned.empty())
        [_overlay refreshControllerVisibility];

    BOOL logRetained = ![reason isEqualToString:@"periodic"];
    for (GCController *controller in currentControllers) {
        if (controller.extendedGamepad == nil)
            continue;
        uintptr_t instance = SunPadControllerInstanceID(controller);
        NSInteger slot = _controllerSlots.SlotFor(instance);
        if (slot < 0) {
            if (logRetained) {
                SunPadLog(@"controller reconciled reason=%@ instance=%@ slot=0 status=%@",
                          reason, SunPadControllerInstanceName(instance), @"no-free-slot");
            }
            continue;
        }

        NSNumber *key = @(instance);
        BOOL newlyConfigured = _configuredControllers[key] != controller;
        controller.playerIndex = SunPadPlayerIndexForSlot(slot);
        if (newlyConfigured) {
            _configuredControllers[key] = controller;
            [self configureController:controller playerSlot:slot];
        }
        if (newlyConfigured || logRetained) {
            SunPadLog(@"controller reconciled reason=%@ instance=%@ slot=%ld status=%@",
                      reason, SunPadControllerInstanceName(instance), (long)(slot + 1),
                      newlyConfigured ? @"assigned" : @"retained");
        }
    }

    GCController *playerOne = [self controllerForPlayerSlot:0];
    if (playerOne != nil)
        [self publishInputFromController:playerOne gamepad:playerOne.extendedGamepad];
}

- (nullable GCController *)controllerForPlayerSlot:(NSInteger)slot {
    if (slot < 0 || slot >= (NSInteger)SunPadControllerSlots::kMaxPlayers)
        return nil;
    uintptr_t instance = _controllerSlots.InstanceAt((std::size_t)slot);
    return instance == 0 ? nil : _configuredControllers[@(instance)];
}

- (void)settingsChanged:(NSNotification *)notification {
    (void)notification;
    SunPadSettings *settings = [SunPadSettings sharedSettings];
    [_coreHost setRenderScale:settings.renderScale];
    [_coreHost setAspectRatioMode:settings.aspectRatioMode];
    [self updateFPSLabel];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CAMetalLayer *layer = (CAMetalLayer *)_gameView.layer;
    layer.drawableSize = CGSizeMake(CGRectGetWidth(_gameView.bounds) * SunPadDrawableScale,
                                    CGRectGetHeight(_gameView.bounds) * SunPadDrawableScale);
    if (!CGSizeEqualToSize(_lastLoggedDrawableSize, layer.drawableSize)) {
        _lastLoggedDrawableSize = layer.drawableSize;
        SunPadLog(@"layout bounds=%@ game=%@ drawable=%@",
                  NSStringFromCGRect(self.view.bounds),
                  NSStringFromCGRect(_gameView.bounds),
                  NSStringFromCGSize(layer.drawableSize));
    }
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat statusWidth = MIN(420.0, CGRectGetWidth(safe) - 32.0);
    _bootActivityIndicator.center = CGPointMake(CGRectGetMidX(safe),
                                                CGRectGetMidY(safe) - 34.0);
    if (_gameDataImportButton.hidden) {
        _bootStatusLabel.frame = CGRectMake(CGRectGetMidX(safe) - statusWidth / 2.0,
                                            CGRectGetMidY(safe) - 4.0,
                                            statusWidth, 80.0);
    } else {
        _bootStatusLabel.frame = CGRectMake(CGRectGetMidX(safe) - statusWidth / 2.0,
                                            CGRectGetMidY(safe) - 104.0,
                                            statusWidth, 132.0);
    }
    CGFloat importWidth = MIN(240.0, CGRectGetWidth(safe) - 64.0);
    _gameDataImportButton.frame = CGRectMake(CGRectGetMidX(safe) - importWidth / 2.0,
                                             CGRectGetMidY(safe) + 44.0,
                                             importWidth, 50.0);
    _fpsLabel.frame = CGRectMake(CGRectGetMinX(safe) + 8.0,
                                 CGRectGetMinY(safe) + 8.0,
                                 140.0, 22.0);
}

- (void)displayConfigurationChanged:(NSNotification *)notification {
    UIScreen *screen = [notification.object isKindOfClass:UIScreen.class]
        ? notification.object : UIScreen.mainScreen;
    SunPadLog(@"display event=%@ bounds=%@ nativeBounds=%@ scale=%.2f nativeScale=%.2f maxFPS=%ld",
              notification.name,
              NSStringFromCGRect(screen.bounds), NSStringFromCGRect(screen.nativeBounds),
              screen.scale, screen.nativeScale, (long)screen.maximumFramesPerSecond);
}

- (void)startGameIfProvisioned {
    if (_coreHost != nil)
        return;
    _gameDataImportButton.hidden = YES;
    _bootStatusLabel.hidden = NO;
    _bootStatusLabel.text = @"Preparing runtime…";
    _bootStatusLabel.accessibilityLabel = @"Preparing runtime";
    [_bootActivityIndicator startAnimating];
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *configPath = [bundle pathForResource:@"dev-config" ofType:@"plist"];
    if (configPath == nil) {
        SunPadLog(@"boot skipped reason=dev config missing");
        _bootStatusLabel.text = @"SunPad needs its local game data before it can start.";
        _bootStatusLabel.accessibilityLabel = _bootStatusLabel.text;
        [_bootActivityIndicator stopAnimating];
        return; // Not a dev-provisioned build; import flow is a later stage.
    }
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
    SunPadSettings *settings = [SunPadSettings sharedSettings];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // App updates can relocate the data-container UUID. On physical devices,
    // derive imported data from the current sandbox instead of trusting an
    // absolute path persisted by a previous installation.
    NSString *supportRoot = [self sunPadSupportRoot];
    NSString *gameDataDirectory = [supportRoot stringByAppendingPathComponent:@"GameData"];

    // Side-by-side diagnostic builds may carry a known progressed save so a
    // performance run can begin in representative gameplay. Seed it exactly
    // once per identifier; production configurations omit these keys.
    NSString *bundledSaveRelativePath = config[@"DeviceBundledSaveRelativePath"];
    NSString *bundledSaveSeedID = config[@"DeviceBundledSaveSeedID"];
    NSString *saveSeedPreference = @"SunPadDeviceBundledSaveSeedID";
    if (bundledSaveRelativePath.length > 0 && bundledSaveSeedID.length > 0 &&
        ![[[NSUserDefaults standardUserDefaults] stringForKey:saveSeedPreference]
            isEqualToString:bundledSaveSeedID]) {
        NSString *bundledSave =
            [bundle.bundlePath stringByAppendingPathComponent:bundledSaveRelativePath];
        NSString *saveDirectory = [supportRoot
            stringByAppendingPathComponent:@"GC/USA/Card A"];
        NSString *saveDestination = [saveDirectory
            stringByAppendingPathComponent:bundledSave.lastPathComponent];
        NSError *saveError = nil;
        [fileManager createDirectoryAtPath:saveDirectory
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&saveError];
        if (saveError == nil) {
            NSString *temporarySave = [saveDestination stringByAppendingString:@".seed"];
            [fileManager removeItemAtPath:temporarySave error:nil];
            if ([fileManager copyItemAtPath:bundledSave toPath:temporarySave error:&saveError]) {
                [fileManager removeItemAtPath:saveDestination error:nil];
                if ([fileManager moveItemAtPath:temporarySave
                                         toPath:saveDestination
                                          error:&saveError]) {
                    [[NSUserDefaults standardUserDefaults]
                        setObject:bundledSaveSeedID forKey:saveSeedPreference];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    SunPadLog(@"diagnostic save seeded file=%@ id=%@",
                              saveDestination.lastPathComponent, bundledSaveSeedID);
                }
            }
        }
        if (saveError != nil)
            SunPadLog(@"diagnostic save seed failed: %@", saveError);
    }

    NSString *currentContainerRoot = [gameDataDirectory stringByAppendingPathComponent:@"GMSE01"];
    BOOL currentRootExists = [fileManager fileExistsAtPath:currentContainerRoot];
    NSString *gameRoot = currentContainerRoot;
#if TARGET_OS_SIMULATOR
    if (!currentRootExists) {
        NSString *developmentRoot = config[@"DevGameRoot"];
        if (developmentRoot.length > 0)
            gameRoot = developmentRoot;
    }
#else
    // A side-by-side diagnostic build can be made self-contained when the
    // CoreDevice data-container transfer service is unavailable. Production
    // builds omit this key and continue to require imported sandbox data.
    if (!currentRootExists) {
        NSString *bundledRootRelativePath = config[@"DeviceBundledGameRootRelativePath"];
        NSString *bundledRoot = bundledRootRelativePath.length > 0
            ? [bundle.bundlePath stringByAppendingPathComponent:bundledRootRelativePath] : nil;
        if (bundledRoot.length > 0 && [fileManager fileExistsAtPath:bundledRoot])
            gameRoot = bundledRoot;
    }
#endif
    if (![settings.extractedGameRoot isEqualToString:gameRoot]) {
        settings.extractedGameRoot = gameRoot;
        [settings synchronize];
    }
    SunPadLog(@"boot data support=%@ root=%@ rootExists=%d persistedRoot=%@",
              supportRoot, gameRoot, currentRootExists,
              settings.extractedGameRoot ?: @"none");

#if !TARGET_OS_SIMULATOR
    // The published app carries no game code: PadMint adds the module
    // translated from the player's own disc.
    NSString *requiredModulePath = [self modulePathFromConfiguration:config];
    if (requiredModulePath.length > 0 && ![fileManager fileExistsAtPath:requiredModulePath]) {
        SunPadLog(@"boot waiting for the game module");
        _bootStatusLabel.text = @"This copy of SunPad has no game code yet. PadMint makes it on a Mac "
                                 "from your own disc and adds it to SunPad; install the SunPad it makes "
                                 "(github.com/chrissotraidis/padmint).";
        _bootStatusLabel.accessibilityLabel = _bootStatusLabel.text;
        [_bootActivityIndicator stopAnimating];
        return;
    }
#endif

    BOOL gameRootIsDirectory = NO;
    BOOL gameRootExists =
        [fileManager fileExistsAtPath:gameRoot isDirectory:&gameRootIsDirectory];
    BOOL gameRootReadable = gameRootExists && gameRootIsDirectory &&
                            [fileManager isReadableFileAtPath:gameRoot];
    if (!gameRootReadable) {
        SunPadLog(@"boot waiting for game data rootExists=%d directory=%d readable=%d",
                  gameRootExists, gameRootIsDirectory,
                  gameRootExists && [fileManager isReadableFileAtPath:gameRoot]);
        [self showGameDataSetupState];
        return;
    }

    NSString *modulePath = [self modulePathFromConfiguration:config];
    if (gameRoot.length == 0 || modulePath.length == 0) {
        SunPadLog(@"boot skipped gameRoot=%d modulePath=%d",
                  gameRoot.length > 0, modulePath.length > 0);
        _bootStatusLabel.text = @"SunPad could not find its local game data.";
        _bootStatusLabel.accessibilityLabel = _bootStatusLabel.text;
        [_bootActivityIndicator stopAnimating];
        return;
    }

    NSString *userDirectory = supportRoot;
    [[NSFileManager defaultManager] createDirectoryAtPath:userDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Boot from the retained image so Dolphin sees the exact FST, physical
    // file offsets, and streaming layout from the user's disc. In-place app
    // installs preserve the file but change the container UUID, so rebase the
    // persisted absolute path when necessary.
    NSString *discFileName = settings.retainedGameDataPath.lastPathComponent;
    if (discFileName.length == 0) {
        NSArray<NSString *> *entries = [fileManager contentsOfDirectoryAtPath:gameDataDirectory
                                                                        error:nil];
        for (NSString *entry in entries) {
            NSString *extension = entry.pathExtension.lowercaseString;
            if ([extension isEqualToString:@"iso"] ||
                [extension isEqualToString:@"gcm"] ||
                [extension isEqualToString:@"rvz"]) {
                discFileName = entry;
                break;
            }
        }
    }
    NSString *rebasedImage = discFileName.length > 0
        ? [gameDataDirectory stringByAppendingPathComponent:discFileName] : @"";
    NSString *discImagePath = rebasedImage;
#if TARGET_OS_SIMULATOR
    if (rebasedImage.length == 0 || ![fileManager fileExistsAtPath:rebasedImage])
        discImagePath = settings.retainedGameDataPath ?: @"";
#else
    if (rebasedImage.length == 0 || ![fileManager fileExistsAtPath:rebasedImage]) {
        NSString *bundledDiscRelativePath = config[@"DeviceBundledDiscImageRelativePath"];
        NSString *bundledDisc = bundledDiscRelativePath.length > 0
            ? [bundle.bundlePath stringByAppendingPathComponent:bundledDiscRelativePath] : nil;
        if (bundledDisc.length > 0 && [fileManager fileExistsAtPath:bundledDisc])
            discImagePath = bundledDisc;
    }
#endif
    if (discImagePath.length > 0 &&
        ![settings.retainedGameDataPath isEqualToString:discImagePath]) {
        settings.retainedGameDataPath = discImagePath;
        [settings synchronize];
    }
    SunPadLog(@"boot disc path=%@ exists=%d", discImagePath.length > 0
              ? discImagePath.lastPathComponent : @"none",
              discImagePath.length > 0 && [fileManager fileExistsAtPath:discImagePath]);

    CAMetalLayer *layer = (CAMetalLayer *)_gameView.layer;
    SunPadLog(@"boot requested gameRootExists=%d discImage=%d moduleExists=%d drawable=%@",
              [fileManager fileExistsAtPath:gameRoot], discImagePath.length > 0,
              [fileManager fileExistsAtPath:modulePath], NSStringFromCGSize(layer.drawableSize));
    _coreHost = [[SunPadCoreHost alloc] initWithLayer:layer];
    __weak SunPadGameViewController *weakSelf = self;
    _bootStatusLabel.text = @"Starting game…";
    _bootStatusLabel.accessibilityLabel = @"Starting game";
    [_coreHost startWithGameRoot:gameRoot
                   discImagePath:discImagePath ?: @""
                      modulePath:modulePath
                   userDirectory:userDirectory
                         onError:^(NSString *message) {
        [weakSelf presentBootError:message];
    }];
}

- (void)showGameDataSetupState {
    [_bootActivityIndicator stopAnimating];
    _bootStatusLabel.hidden = NO;

    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    paragraph.paragraphSpacing = 8.0;
    NSDictionary *titleAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:24.0 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: UIColor.whiteColor,
        NSParagraphStyleAttributeName: paragraph,
    };
    NSDictionary *bodyAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.82],
        NSParagraphStyleAttributeName: paragraph,
    };
    NSMutableAttributedString *message = [[NSMutableAttributedString alloc]
        initWithString:@"Game data required\n" attributes:titleAttributes];
    [message appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"SunPad does not include game files. Choose your own legally obtained Super Mario Sunshine USA disc image (GMSE01, revision 0) to continue."
             attributes:bodyAttributes]];
    _bootStatusLabel.attributedText = message;
    _bootStatusLabel.accessibilityLabel =
        @"Game data required. SunPad does not include game files. Choose your own legally obtained Super Mario Sunshine USA disc image, GMSE01 revision zero, to continue.";
    _gameDataImportButton.hidden = NO;
    [self.view setNeedsLayout];
}

- (void)presentBootError:(NSString *)message {
    _bootStatusLabel.text = @"SunPad could not start.";
    _bootStatusLabel.accessibilityLabel = _bootStatusLabel.text;
    [_bootActivityIndicator stopAnimating];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SunPad could not start"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)startInputConsumer {
    // Feed the game thread the merged touch+controller snapshot at 60 Hz.
    if (_controllerTimer)
        return;
    _controllerTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                              dispatch_get_main_queue());
    dispatch_source_set_timer(_controllerTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              1.0 / 60.0 * NSEC_PER_SEC, 0);
    __weak SunPadGameViewController *weakSelf = self;
    dispatch_source_set_event_handler(_controllerTimer, ^{
        [weakSelf publishMergedInput];
    });
    dispatch_resume(_controllerTimer);
}

- (void)publishMergedInput {
    SunPadInputState merged = [[SunPadInputMixer sharedMixer] consumeMergedState];
    [_coreHost publishInput:merged];
}

- (void)pauseRuntimeForApplicationLifecycle {
    _performanceLogSeconds = 0;
    _hasPerformanceUsageBaseline = NO;
    [_coreHost pauseRuntimeForSystemEvent];
}

- (void)resumeRuntimeForApplicationLifecycle {
    _performanceLogSeconds = 0;
    _hasPerformanceUsageBaseline = NO;
    [self reconcileControllersForReason:@"foreground"];
    [self restoreOverlayAfterForeground];
    [_coreHost resumeRuntimeAfterSystemEvent];
}

- (void)restoreOverlayAfterForeground {
    if (_overlay.superview != self.view) {
        [_overlay removeFromSuperview];
        _overlay.frame = self.view.bounds;
        _overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:_overlay];
        SunPadLog(@"overlay reattached after foreground surface change");
    }
    _overlay.hidden = NO;
    _overlay.alpha = 1.0;
    [self.view bringSubviewToFront:_overlay];
    [_overlay refreshControllerVisibility];
    [_overlay applySettings];
    [_overlay setNeedsLayout];

    __weak SunPadGameViewController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SunPadGameViewController *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_overlay.superview != strongSelf.view)
            return;
        [strongSelf.view bringSubviewToFront:strongSelf->_overlay];
        [strongSelf->_overlay setNeedsLayout];
    });
}

#pragma mark - SunPadGameOverlayDelegate

- (void)gameOverlayRequestsGameDataChange:(SunPadGameOverlay *)overlay {
    (void)overlay;
    // Document-picker game-data import flow is wired in the app delegate; the
    // overlay requests a change/reimport here.
    [self presentGameDataImport];
}

- (void)gameOverlayRequestsGameDataFolderImport:(SunPadGameOverlay *)overlay {
    (void)overlay;
    [self presentGameDataFolderImport];
}

- (void)gameOverlayRequestsGameDataRemoval:(SunPadGameOverlay *)overlay {
    (void)overlay;
    if (_coreHost != nil) {
        [_coreHost stop];
        _coreHost = nil;
    }

    NSString *dataDirectory = [[self sunPadSupportRoot]
        stringByAppendingPathComponent:@"GameData"];
    NSError *error = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:dataDirectory] &&
        ![[NSFileManager defaultManager] removeItemAtPath:dataDirectory error:&error]) {
        [self startGameIfProvisioned];
        [self presentBootError:[NSString stringWithFormat:
            @"Could not remove stored game data: %@", error.localizedDescription]];
        return;
    }

    SunPadSettings *settings = [SunPadSettings sharedSettings];
    settings.retainedGameDataPath = nil;
    settings.extractedGameRoot = nil;
    [settings synchronize];
    [self showGameDataSetupState];
    SunPadLog(@"stored game data removed");
}

- (void)gameOverlayRequestsControllerMapping:(SunPadGameOverlay *)overlay {
    (void)overlay;
    [self presentControllerMapping];
}

- (NSString *)gameOverlayDiagnosticContext:(SunPadGameOverlay *)overlay {
    (void)overlay;
    NSBundle *bundle = NSBundle.mainBundle;
    SunPadSettings *settings = [SunPadSettings sharedSettings];
    NSMutableArray<NSString *> *controllers = [NSMutableArray array];
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil) {
            [controllers addObject:controller.vendorName ?: controller.productCategory ?: @"unknown"];
        }
    }
    NSString *screenshot = @"none";
    if (_lastScreenshotMarker != nil) {
        screenshot = [NSString stringWithFormat:@"%.1f-seconds-ago",
            MAX(0.0, -[_lastScreenshotMarker timeIntervalSinceNow])];
    }
    NSString *performance = _lastPerformanceSummary;
    if (performance.length == 0) {
        performance = [NSString stringWithFormat:
            @"fps=%.1f vps=%.1f speedRatio=%.3f efb=%@",
            [_coreHost currentFPS], [_coreHost currentVPS], [_coreHost currentSpeed],
            [_coreHost efbResolution].length > 0 ? [_coreHost efbResolution] : @"unavailable"];
    }
    return [NSString stringWithFormat:
        @"appVersion=%@ build=%@\n"
         @"platform=%@ os=%@\n"
         @"screen=%@ native=%@ drawable=%@\n"
         @"storedSettings renderScale=%ld aspect=%ld experimentalPerformance=%d experimental60FPS=%d\n"
         @"controllers count=%lu names=%@\n"
         @"recentScreenshot=%@\n"
         @"performance %@\n%@",
        [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown",
        UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"iPad" : @"iPhone",
        NSProcessInfo.processInfo.operatingSystemVersionString,
        NSStringFromCGRect(UIScreen.mainScreen.bounds),
        NSStringFromCGRect(UIScreen.mainScreen.nativeBounds),
        NSStringFromCGSize(((CAMetalLayer *)_gameView.layer).drawableSize),
        (long)settings.renderScale, (long)settings.aspectRatioMode,
        settings.experimentalPerformanceMode, settings.experimental60FPS,
        (unsigned long)controllers.count,
        controllers.count > 0 ? [controllers componentsJoinedByString:@", "] : @"none",
        screenshot, performance, [_coreHost diagnosticSummary]];
}

- (NSString *)gameOverlayPerformanceProfile:(SunPadGameOverlay *)overlay {
    (void)overlay;
    return [_coreHost currentPerformanceProfile];
}

- (GCController *)firstExtendedController {
    GCController *playerOne = [self controllerForPlayerSlot:0];
    if (playerOne != nil)
        return playerOne;
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil)
            return controller;
    }
    return nil;
}

- (void)presentControllerMapping {
    GCController *controller = [self firstExtendedController];
    SunPadControllerButtonMapping mapping = [SunPadControllerMappingStore mapping];
    NSString *controllerName = controller.vendorName ?: controller.productCategory;
    NSString *message = controllerName.length > 0
        ? [NSString stringWithFormat:@"Connected: %@\nOnly A, B, X, Y, and Z are remapped. Analog triggers, sticks, D-pad, Start, and the right shoulder spray stay unchanged.",
                                     controllerName]
        : @"No extended controller is connected. You can review or reset the saved mapping; connect a controller to test it.";
    if (controller.physicalInputProfile.hasRemappedElements) {
        message = [message stringByAppendingString:
            @"\n\niOS controller customization is also active, so Apple applies that remap before SunPad."];
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Controller Button Mapping"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    const uint16_t gameButtons[] = {
        SunPadButtonA, SunPadButtonB, SunPadButtonX, SunPadButtonY, SunPadButtonZ,
    };
    __weak SunPadGameViewController *weakSelf = self;
    for (uint16_t gameButton : gameButtons) {
        NSString *title = [NSString stringWithFormat:@"%@ — %@",
            SunPadGameButtonName(gameButton),
            SunPadPhysicalControllerButtonName(
                SunPadMappedPhysicalButton(mapping, gameButton))];
        [alert addAction:[UIAlertAction actionWithTitle:title
                                                style:UIAlertActionStyleDefault
                                              handler:^(__kindof UIAlertAction *action) {
            (void)action;
            [weakSelf presentPhysicalButtonChoicesForGameButton:gameButton];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset to Default"
                                            style:UIAlertActionStyleDestructive
                                          handler:^(__kindof UIAlertAction *action) {
        (void)action;
        [SunPadControllerMappingStore reset];
        [[SunPadInputMixer sharedMixer] clearInputFromTouch:NO];
        SunPadLog(@"controller mapping reset to default");
        [weakSelf presentControllerMapping];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Done"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentPhysicalButtonChoicesForGameButton:(uint16_t)gameButton {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:SunPadGameButtonName(gameButton)
                         message:@"Choose the physical controller button. If it is already assigned, the two assignments swap."
                  preferredStyle:UIAlertControllerStyleAlert];
    const SunPadPhysicalControllerButton physicalButtons[] = {
        SunPadPhysicalControllerButtonA,
        SunPadPhysicalControllerButtonB,
        SunPadPhysicalControllerButtonX,
        SunPadPhysicalControllerButtonY,
        SunPadPhysicalControllerButtonLeftShoulder,
    };
    __weak SunPadGameViewController *weakSelf = self;
    for (SunPadPhysicalControllerButton physicalButton : physicalButtons) {
        [alert addAction:[UIAlertAction
            actionWithTitle:SunPadPhysicalControllerButtonName(physicalButton)
                      style:UIAlertActionStyleDefault
                    handler:^(__kindof UIAlertAction *action) {
            (void)action;
            SunPadControllerButtonMapping mapping = [SunPadControllerMappingStore mapping];
            mapping = SunPadControllerButtonMappingByAssigning(
                mapping, physicalButton, gameButton);
            [SunPadControllerMappingStore setMapping:mapping];
            [[SunPadInputMixer sharedMixer] clearInputFromTouch:NO];
            SunPadLog(@"controller mapping changed game=%@ physical=%@",
                      SunPadGameButtonName(gameButton),
                      SunPadPhysicalControllerButtonName(physicalButton));
            [weakSelf presentControllerMapping];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:^(__kindof UIAlertAction *action) {
        (void)action;
        [weakSelf presentControllerMapping];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentGameDataImport {
    NSArray<UTType *> *types = @[
        [UTType typeWithFilenameExtension:@"iso"],
        [UTType typeWithFilenameExtension:@"gcm"],
        UTTypeData,
    ];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types
                                                               asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    picker.shouldShowFileExtensions = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (NSArray<NSURL *> *)gameImagesInDocumentsDirectory {
    NSURL *documentsURL = [[[NSFileManager defaultManager]
        URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    if (documentsURL == nil)
        return @[];

    NSArray<NSURL *> *entries = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:documentsURL
      includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:nil];
    NSMutableArray<NSURL *> *images = [NSMutableArray array];
    NSSet<NSString *> *extensions = [NSSet setWithArray:@[@"iso", @"gcm"]];
    for (NSURL *entry in entries) {
        NSNumber *isRegularFile = nil;
        [entry getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (isRegularFile.boolValue &&
            [extensions containsObject:entry.pathExtension.lowercaseString]) {
            [images addObject:entry];
        }
    }
    [images sortUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        return [left.lastPathComponent localizedStandardCompare:right.lastPathComponent];
    }];
    return images;
}

- (void)presentGameDataFolderImport {
    NSArray<NSURL *> *images = [self gameImagesInDocumentsDirectory];
    if (images.count == 1) {
        [self importGameDataFromURL:images.firstObject];
        return;
    }

    NSString *message = images.count == 0
        ? @"No ISO or GCM was found. In Files, place the image directly in On My iPhone → SunPad, then try again."
        : @"Choose an image from On My iPhone → SunPad.";
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"SunPad Folder"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    __weak SunPadGameViewController *weakSelf = self;
    for (NSURL *imageURL in images) {
        [alert addAction:[UIAlertAction actionWithTitle:imageURL.lastPathComponent
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__kindof UIAlertAction *action) {
            (void)action;
            [weakSelf importGameDataFromURL:imageURL];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    if (url == nil)
        return;
    [self importGameDataFromURL:url];
}

- (void)importGameDataFromURL:(NSURL *)url {
    UIAlertController *progressAlert =
        [UIAlertController alertControllerWithTitle:@"Importing Game Data"
                                            message:@"Validating and copying the disc…"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];

    NSString *supportRoot = [self sunPadSupportRoot];
    NSString *stagingDirectory = [supportRoot stringByAppendingPathComponent:
        [NSString stringWithFormat:@"GameData.import-%@", NSUUID.UUID.UUIDString]];
    NSString *stagedImage = [stagingDirectory stringByAppendingPathComponent:@"GMSE01.iso"];
    NSString *stagedRoot = [stagingDirectory stringByAppendingPathComponent:@"GMSE01"];
    __weak SunPadGameViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSString *> *supportEntries = [[NSFileManager defaultManager]
            contentsOfDirectoryAtPath:supportRoot error:nil];
        for (NSString *entry in supportEntries) {
            if ([entry hasPrefix:@"GameData.import-"] &&
                ![[supportRoot stringByAppendingPathComponent:entry]
                    isEqualToString:stagingDirectory]) {
                [[NSFileManager defaultManager]
                    removeItemAtPath:[supportRoot stringByAppendingPathComponent:entry]
                              error:nil];
            }
        }

        BOOL securityScoped = [url startAccessingSecurityScopedResource];
        NSString *validationError = [weakSelf validateGameDataAtURL:url];
        NSError *copyError = nil;
        if (validationError == nil) {
            [[NSFileManager defaultManager] createDirectoryAtPath:stagingDirectory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&copyError];
        }
        if (validationError == nil && copyError == nil) {
            [[NSFileManager defaultManager] copyItemAtURL:url
                                                    toURL:[NSURL fileURLWithPath:stagedImage]
                                                    error:&copyError];
        }
        if (validationError == nil && copyError == nil) {
            NSString *hash = SunPadSHA256ForFile(stagedImage, &copyError);
            if (copyError == nil && ![hash isEqualToString:SunPadSupportedImageSHA256])
                validationError = @"The image SHA-256 does not match supported GMSE01 USA revision 0 data.";
        }
        if (securityScoped)
            [url stopAccessingSecurityScopedResource];

        dispatch_async(dispatch_get_main_queue(), ^{
            SunPadGameViewController *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            if (validationError != nil || copyError != nil) {
                [[NSFileManager defaultManager] removeItemAtPath:stagingDirectory error:nil];
                [progressAlert dismissViewControllerAnimated:YES completion:^{
                    [strongSelf presentBootError:validationError ?: [NSString stringWithFormat:
                        @"Could not retain the game image: %@", copyError.localizedDescription]];
                }];
                return;
            }

            progressAlert.message = @"Extracting the disc…";
            [SunPadDiscExtractor extractImageAtPath:stagedImage
                                       toDirectory:stagedRoot
                                           progress:^(NSString *status, double fraction) {
                progressAlert.message = [NSString stringWithFormat:@"%@ (%.0f%%)",
                                         status, fraction * 100.0];
            }
                                         completion:^(BOOL ok, NSString *error) {
                SunPadGameViewController *completedSelf = weakSelf;
                if (completedSelf == nil)
                    return;
                if (!ok) {
                    [[NSFileManager defaultManager] removeItemAtPath:stagingDirectory error:nil];
                    [progressAlert dismissViewControllerAnimated:YES completion:^{
                        [completedSelf presentBootError:error ?: @"Extraction failed."];
                    }];
                    return;
                }

                NSArray<NSString *> *required = @[
                    @"sys/boot.bin", @"sys/bi2.bin", @"sys/apploader.img",
                    @"sys/fst.bin", @"sys/main.dol", @"files/opening.bnr",
                    @"files/AudioRes/mSound.asn", @"files/data/common.szs",
                ];
                for (NSString *relative in required) {
                    if (![[NSFileManager defaultManager] fileExistsAtPath:
                          [stagedRoot stringByAppendingPathComponent:relative]]) {
                        [[NSFileManager defaultManager] removeItemAtPath:stagingDirectory error:nil];
                        [progressAlert dismissViewControllerAnimated:YES completion:^{
                            [completedSelf presentBootError:@"The extracted game data is incomplete."];
                        }];
                        return;
                    }
                }
                if (SunPadRegularFileCount([stagedRoot stringByAppendingPathComponent:@"files"]) != 174) {
                    [[NSFileManager defaultManager] removeItemAtPath:stagingDirectory error:nil];
                    [progressAlert dismissViewControllerAnimated:YES completion:^{
                        [completedSelf presentBootError:@"The extracted game file count is incomplete."];
                    }];
                    return;
                }

                if (completedSelf->_coreHost != nil) {
                    [completedSelf->_coreHost stop];
                    completedSelf->_coreHost = nil;
                }
                NSString *dataDirectory = [supportRoot stringByAppendingPathComponent:@"GameData"];
                NSFileManager *fileManager = [NSFileManager defaultManager];
                NSError *swapError = nil;
                if ([fileManager fileExistsAtPath:dataDirectory]) {
                    NSURL *resultURL = nil;
                    [fileManager replaceItemAtURL:[NSURL fileURLWithPath:dataDirectory]
                                    withItemAtURL:[NSURL fileURLWithPath:stagingDirectory]
                                   backupItemName:nil options:0
                                 resultingItemURL:&resultURL error:&swapError];
                } else {
                    [fileManager moveItemAtPath:stagingDirectory
                                         toPath:dataDirectory error:&swapError];
                }
                if (swapError != nil) {
                    [completedSelf startGameIfProvisioned];
                    [progressAlert dismissViewControllerAnimated:YES completion:^{
                        [completedSelf presentBootError:[NSString stringWithFormat:
                            @"Could not activate the imported game data: %@",
                            swapError.localizedDescription]];
                    }];
                    return;
                }

                NSString *destination = [dataDirectory stringByAppendingPathComponent:@"GMSE01.iso"];
                NSString *extractRoot = [dataDirectory stringByAppendingPathComponent:@"GMSE01"];
                SunPadSettings *settings = [SunPadSettings sharedSettings];
                settings.retainedGameDataPath = destination;
                settings.extractedGameRoot = extractRoot;
                [settings synchronize];
                SunPadLog(@"game data import activated filename=%@", destination.lastPathComponent);
                [progressAlert dismissViewControllerAnimated:YES completion:^{
                    [completedSelf startGameIfProvisioned];
                }];
            }];
        });
    });
}

- (nullable NSString *)validateGameDataAtURL:(NSURL *)url {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:url.path];
    if (handle == nil)
        return @"The selected file could not be opened.";
    NSData *header = [handle readDataOfLength:0x100];
    [handle closeFile];
    if (header.length < 0x100)
        return @"The file is too small to be a GameCube image.";

    NSNumber *fileSize = [[[NSFileManager defaultManager]
        attributesOfItemAtPath:url.path error:nil] objectForKey:NSFileSize];
    if (fileSize.unsignedLongLongValue != 1459978240ULL)
        return @"The image size does not match the supported GMSE01 USA revision 0 disc.";

    const uint8_t *bytes = (const uint8_t *)header.bytes;
    uint32_t magic = CFSwapInt32BigToHost(*(uint32_t *)(bytes + 0x1C));
    if (magic != 0xC2339F3D)
        return @"The file is not a GameCube disc image (bad magic).";
    char gameId[7] = {0};
    // The GameCube disc header starts with the six-character game code.
    memcpy(gameId, bytes + 0x00, 6);
    if (strncmp(gameId, "GMSE01", 6) != 0)
        return [NSString stringWithFormat:@"Unsupported game ID '%s'; SunPad currently supports GMSE01 (Super Mario Sunshine USA).", gameId];
    if (bytes[6] != 0 || bytes[7] != 0)
        return @"SunPad currently supports disc 0, revision 0 only.";
    return nil;
}

- (NSString *)sunPadSupportRoot {
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"]
        stringByAppendingPathComponent:@"SunPad"];
}

@end
