#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>

#import "SunPadCoreHost.h"
#import "SunPadDiagnostics.h"
#import "SunPadTVControllerManager.h"

@interface SunPadTVViewController : UIViewController
@property(nonatomic, strong) UILabel *statusLabel;
@end

@interface SunPadTVSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@interface SunPadTVAppDelegate : UIResponder <UIApplicationDelegate>
@end

static SunPadCoreHost *SunPadTVRuntimeHost;
static SunPadTVControllerManager *SunPadTVControllerInput;

static NSString *SunPadTVSupportRoot(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"SunPad"];
}

static BOOL SunPadTVReadableRegularFile(NSString *path) {
    BOOL isDirectory = NO;
    NSFileManager *fileManager = NSFileManager.defaultManager;
    return [fileManager fileExistsAtPath:path isDirectory:&isDirectory] &&
           !isDirectory && [fileManager isReadableFileAtPath:path];
}

static void SunPadTVSetStatus(SunPadTVViewController *controller,
                              NSString *text,
                              BOOL hidden) {
    controller.statusLabel.text = text;
    controller.statusLabel.accessibilityLabel = text;
    controller.statusLabel.hidden = hidden;
}

static void SunPadTVStopRuntime(void) {
    [SunPadTVControllerInput stop];
    SunPadTVControllerInput = nil;
    SunPadCoreHost *host = SunPadTVRuntimeHost;
    SunPadTVRuntimeHost = nil;
    [host stop];
}

static void SunPadTVStartRuntime(SunPadTVViewController *controller) {
    if (SunPadTVRuntimeHost != nil)
        return;

    NSString *supportRoot = SunPadTVSupportRoot();
    NSString *gameRoot = [supportRoot stringByAppendingPathComponent:@"Game"];
    NSString *mainDol = [gameRoot stringByAppendingPathComponent:@"sys/main.dol"];
    NSString *modulePath =
        [supportRoot stringByAppendingPathComponent:@"gGMSE01_recomp.dylib"];

    // The runtime has no bundled-data fallback: both private inputs must be
    // present before the host is created or started.
    if (!SunPadTVReadableRegularFile(mainDol) ||
        !SunPadTVReadableRegularFile(modulePath)) {
        SunPadTVSetStatus(controller, @"SunPad - game data not provisioned", NO);
        return;
    }

    CALayer *layer = controller.view.layer;
    if (![layer isKindOfClass:CAMetalLayer.class]) {
        SunPadDiagnosticsStart();
        SunPadLog(@"tvOS runtime start failed: expected CAMetalLayer");
        SunPadTVSetStatus(controller, @"SunPad - runtime unavailable", NO);
        return;
    }

    SunPadDiagnosticsStart();
    SunPadTVSetStatus(controller, @"SunPad - starting runtime", YES);

    SunPadCoreHost *host = [[SunPadCoreHost alloc]
        initWithLayer:(CAMetalLayer *)layer];
    SunPadTVRuntimeHost = host;
    SunPadTVControllerInput = [[SunPadTVControllerManager alloc] initWithHost:host];
    [SunPadTVControllerInput start];
    __weak SunPadTVViewController *weakController = controller;
    [host startWithGameRoot:gameRoot
              discImagePath:@""
                modulePath:modulePath
             userDirectory:supportRoot
                   onError:^(NSString *message) {
        SunPadTVViewController *strongController = weakController;
        if (strongController != nil)
            SunPadTVSetStatus(strongController, @"SunPad - runtime failed", NO);
        SunPadLog(@"tvOS runtime error: %@", message);
    }];
}

@implementation SunPadTVViewController (SunPadRuntime)

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    SunPadTVStartRuntime(self);
}

@end

@implementation SunPadTVSceneDelegate (SunPadRuntime)

- (void)sceneDidBecomeActive:(UIScene *)scene {
    (void)scene;
    [SunPadTVRuntimeHost resumeRuntimeAfterSystemEvent];
    [SunPadTVControllerInput activate];
}

- (void)sceneWillResignActive:(UIScene *)scene {
    (void)scene;
    [SunPadTVControllerInput deactivate];
    [SunPadTVRuntimeHost pauseRuntimeForSystemEvent];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    (void)scene;
    [SunPadTVControllerInput deactivate];
    [SunPadTVRuntimeHost pauseRuntimeForSystemEvent];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    (void)scene;
    SunPadTVStopRuntime();
}

@end

@implementation SunPadTVAppDelegate (SunPadRuntime)

- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    SunPadTVStopRuntime();
}

@end
