#import <UIKit/UIKit.h>
#import <os/proc.h>

#import "SunPadDiagnostics.h"
#import "SunPadGameViewController.h"
#import "SunPadSettings.h"

@interface SunPadSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@interface SunPadAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic) UIBackgroundTaskIdentifier saveFlushTask;
- (void)beginSaveFlushGraceForApplication:(UIApplication *)application;
- (void)endSaveFlushGraceForApplication:(UIApplication *)application reason:(NSString *)reason;
@end

static void SunPadRestorePreferencesIfRequested(void) {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    if (![arguments containsObject:@"-sunpadRestorePreferences"])
        return;

    NSString *restorePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"tmp"]
        stringByAppendingPathComponent:@"SunPadPreferencesRestore.plist"];
    NSDictionary *restored = [NSDictionary dictionaryWithContentsOfFile:restorePath];
    if (restored.count == 0) {
        SunPadLog(@"preferences restore skipped path=%@ reason=missing or empty", restorePath);
        return;
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in restored)
        [defaults setObject:restored[key] forKey:key];
    [defaults synchronize];
    [[NSFileManager defaultManager] removeItemAtPath:restorePath error:nil];
    SunPadLog(@"preferences restored keys=%lu", (unsigned long)restored.count);
}

static void SunPadApplyExperimentSafetyMigration(void) {
    static NSInteger const kSafetyResetVersion = 1;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSInteger appliedVersion = [defaults integerForKey:@"SunPadExperimentSafetyResetVersion"];
    if (appliedVersion >= kSafetyResetVersion)
        return;

    SunPadSettings *settings = [SunPadSettings sharedSettings];
    BOOL performanceWasEnabled = settings.experimentalPerformanceMode;
    BOOL sixtyFPSWasEnabled = settings.experimental60FPS;
    settings.experimentalPerformanceMode = NO;
    settings.experimental60FPS = NO;
    [defaults setInteger:kSafetyResetVersion forKey:@"SunPadExperimentSafetyResetVersion"];
    [settings synchronize];
    SunPadLog(@"experiment safety migration version=%ld performanceWasEnabled=%d "
              "sixtyFPSWasEnabled=%d result=supported-default",
              (long)kSafetyResetVersion, performanceWasEnabled, sixtyFPSWasEnabled);
}

@implementation SunPadAppDelegate

- (UIInterfaceOrientationMask)application:(UIApplication *)application
    supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    (void)application;
    (void)window;
    // Super Mario Sunshine is a landscape-only experience.
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;

    SunPadDiagnosticsStart();
    SunPadRestorePreferencesIfRequested();
    SunPadApplyExperimentSafetyMigration();
    self.saveFlushTask = UIBackgroundTaskInvalid;
    UIScreen *screen = UIScreen.mainScreen;
    SunPadLog(@"launch screen bounds=%@ nativeBounds=%@ scale=%.2f nativeScale=%.2f maxFPS=%ld",
              NSStringFromCGRect(screen.bounds), NSStringFromCGRect(screen.nativeBounds),
              screen.scale, screen.nativeScale, (long)screen.maximumFramesPerSecond);

    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
    options:(UISceneConnectionOptions *)options {
    (void)application;
    (void)options;
    UISceneConfiguration *configuration =
        [[UISceneConfiguration alloc] initWithName:@"SunPad" sessionRole:session.role];
    configuration.delegateClass = SunPadSceneDelegate.class;
    return configuration;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    SunPadLog(@"lifecycle didBecomeActive");
    [self endSaveFlushGraceForApplication:application reason:@"active"];
    [(SunPadGameViewController *)self.window.rootViewController
        resumeRuntimeForApplicationLifecycle];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    SunPadLog(@"lifecycle willResignActive");
    [(SunPadGameViewController *)self.window.rootViewController
        pauseRuntimeForApplicationLifecycle];
    [self beginSaveFlushGraceForApplication:application];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    SunPadLog(@"lifecycle didEnterBackground");
}

- (void)beginSaveFlushGraceForApplication:(UIApplication *)application {
    // Dolphin's GCI-folder backend flushes one second after writes stop. The
    // runtime was paused in applicationWillResignActive, so keep the process
    // alive briefly enough for that existing save thread to finish without
    // forcing a shutdown or reaching into its private memory-card state.
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    __weak SunPadAppDelegate *weakSelf = self;
    task = [application beginBackgroundTaskWithName:@"SunPad save flush grace"
                                  expirationHandler:^{
        SunPadAppDelegate *strongSelf = weakSelf;
        if (strongSelf.saveFlushTask == task)
            [strongSelf endSaveFlushGraceForApplication:application reason:@"expired"];
    }];
    if (task == UIBackgroundTaskInvalid) {
        SunPadLog(@"lifecycle save flush grace unavailable");
        return;
    }

    if (self.saveFlushTask != UIBackgroundTaskInvalid)
        [self endSaveFlushGraceForApplication:application reason:@"replaced"];
    self.saveFlushTask = task;
    SunPadLog(@"lifecycle save flush grace started");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        SunPadAppDelegate *strongSelf = weakSelf;
        if (strongSelf.saveFlushTask == task)
            [strongSelf endSaveFlushGraceForApplication:application reason:@"timer"];
    });
}

- (void)endSaveFlushGraceForApplication:(UIApplication *)application reason:(NSString *)reason {
    UIBackgroundTaskIdentifier task = self.saveFlushTask;
    if (task == UIBackgroundTaskInvalid)
        return;
    self.saveFlushTask = UIBackgroundTaskInvalid;
    [application endBackgroundTask:task];
    SunPadLog(@"lifecycle save flush grace ended reason=%@", reason);
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    (void)application;
    SunPadLog(@"lifecycle willEnterForeground");
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    (void)application;
    SunPadLog(@"memory warning physical=%llu available=%llu",
              (unsigned long long)NSProcessInfo.processInfo.physicalMemory,
              (unsigned long long)os_proc_available_memory());
}

- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    SunPadLog(@"lifecycle willTerminate");
}

@end

@implementation SunPadSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
    options:(UISceneConnectionOptions *)options {
    (void)session;
    (void)options;
    if (![scene isKindOfClass:UIWindowScene.class])
        return;

    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[SunPadGameViewController alloc] init];
    ((SunPadAppDelegate *)UIApplication.sharedApplication.delegate).window = self.window;
    [self.window makeKeyAndVisible];
    SunPadLog(@"lifecycle scene connected");
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    (void)scene;
    SunPadAppDelegate *delegate = (SunPadAppDelegate *)UIApplication.sharedApplication.delegate;
    if (delegate.window == self.window)
        delegate.window = nil;
    self.window = nil;
}

// Keep the existing pause/resume and save-flush path as the single owner of
// runtime lifecycle work. UIKit delivers these events to the scene on iOS 27.
- (void)sceneDidBecomeActive:(UIScene *)scene {
    (void)scene;
    [(SunPadAppDelegate *)UIApplication.sharedApplication.delegate
        applicationDidBecomeActive:UIApplication.sharedApplication];
}

- (void)sceneWillResignActive:(UIScene *)scene {
    (void)scene;
    [(SunPadAppDelegate *)UIApplication.sharedApplication.delegate
        applicationWillResignActive:UIApplication.sharedApplication];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    (void)scene;
    [(SunPadAppDelegate *)UIApplication.sharedApplication.delegate
        applicationDidEnterBackground:UIApplication.sharedApplication];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    (void)scene;
    [(SunPadAppDelegate *)UIApplication.sharedApplication.delegate
        applicationWillEnterForeground:UIApplication.sharedApplication];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SunPadAppDelegate class]));
    }
}
