#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

@interface SunPadTVView : UIView
@end

@implementation SunPadTVView

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = YES;
        self.backgroundColor = UIColor.blackColor;
        CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
        metalLayer.device = MTLCreateSystemDefaultDevice();
        metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        metalLayer.framebufferOnly = YES;
        metalLayer.backgroundColor = UIColor.blackColor.CGColor;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
    metalLayer.drawableSize = CGSizeMake(CGRectGetWidth(self.bounds) * self.contentScaleFactor,
                                        CGRectGetHeight(self.bounds) * self.contentScaleFactor);
}

@end

@interface SunPadTVViewController : UIViewController
@property(nonatomic, strong) UILabel *statusLabel;
@end

@implementation SunPadTVViewController

- (void)loadView {
    SunPadTVView *rootView = [[SunPadTVView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    self.view = rootView;

    UILabel *statusLabel = [[UILabel alloc] init];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.text = @"SunPad - game data not provisioned";
    statusLabel.textAlignment = NSTextAlignmentCenter;
    statusLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    statusLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightRegular];
    statusLabel.adjustsFontSizeToFitWidth = YES;
    statusLabel.minimumScaleFactor = 0.75;
    self.statusLabel = statusLabel;
    [rootView addSubview:statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [statusLabel.centerXAnchor constraintEqualToAnchor:rootView.centerXAnchor],
        [statusLabel.bottomAnchor constraintEqualToAnchor:rootView.safeAreaLayoutGuide.bottomAnchor
                                                 constant:-40.0],
    ]];
}

@end

@interface SunPadTVSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation SunPadTVSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
    (void)session;
    (void)connectionOptions;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.rootViewController = [[SunPadTVViewController alloc] init];
    [self.window makeKeyAndVisible];
}

@end

@interface SunPadTVAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation SunPadTVAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([SunPadTVAppDelegate class]));
    }
}
