#import "SunPadGameOverlay.h"

#import "SunPadDiagnostics.h"
#import "SunPadControllerRumble.h"
#import "SunPadInputMixer.h"
#import "SunPadSettings.h"

#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cmath>

@interface SunPadStickView : UIView
@property(nonatomic, copy) void (^valueChanged)(float x, float y);
@property(nonatomic, readonly) BOOL active;
- (void)applyBaseColor:(UIColor *)baseColor thumbColor:(UIColor *)thumbColor;
- (void)reset;
@end

@implementation SunPadStickView {
    UIView *_thumb;
    float _valueX, _valueY;
    BOOL _active;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = NO;
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.34].CGColor;
        self.layer.borderWidth = 2.0;
        _thumb = [[UIView alloc] initWithFrame:CGRectZero];
        _thumb.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.32];
        _thumb.userInteractionEnabled = NO;
        [self addSubview:_thumb];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = std::min(self.bounds.size.width, self.bounds.size.height);
    self.layer.cornerRadius = side * 0.5;
    CGFloat thumbDiameter = side * 0.42;
    _thumb.bounds = CGRectMake(0, 0, thumbDiameter, thumbDiameter);
    _thumb.layer.cornerRadius = thumbDiameter * 0.5;
    [self updateThumbCenter];
}

- (void)updateThumbCenter {
    CGFloat half = self.bounds.size.width * 0.5;
    CGFloat maxTravel = half - _thumb.bounds.size.width * 0.5 - 3.0;
    _thumb.center = CGPointMake(half + _valueX * maxTravel,
                                half + _valueY * maxTravel);
}

- (void)setValueX:(float)x y:(float)y {
    _valueX = x;
    _valueY = y;
    [self updateThumbCenter];
}

- (BOOL)active {
    return _active;
}

- (void)applyBaseColor:(UIColor *)baseColor thumbColor:(UIColor *)thumbColor {
    self.backgroundColor = baseColor;
    _thumb.backgroundColor = thumbColor;
}

- (void)reset {
    _active = NO;
    _valueX = _valueY = 0.0f;
    [self updateThumbCenter];
    if (self.valueChanged)
        self.valueChanged(0.0f, 0.0f);
}

- (void)handleTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:self];
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat radius = std::max<CGFloat>(1.0, std::min(self.bounds.size.width,
                                                     self.bounds.size.height) * 0.5);
    CGFloat dx = (p.x - center.x) / radius;
    CGFloat dy = (p.y - center.y) / radius;
    CGFloat length = hypot(dx, dy);
    if (length > 1.0) {
        dx /= length;
        dy /= length;
    }
    CGFloat thumbRadius = _thumb.bounds.size.width * 0.5;
    CGFloat travel = std::max<CGFloat>(0.0, radius - thumbRadius - 4.0);
    _thumb.center = CGPointMake(center.x + dx * travel, center.y + dy * travel);
    // BellPad: positive Y is up (negate UIKit's down-positive coordinate).
    _valueX = (float)dx;
    _valueY = (float)(-dy);
    _active = YES;
    if (self.valueChanged)
        self.valueChanged(_valueX, _valueY);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:touches.anyObject];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self handleTouch:touches.anyObject];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self reset];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self reset];
}

@end

@interface SunPadGameButton : UIButton
@property(nonatomic, assign) uint16_t inputMask;
@end

@implementation SunPadGameButton
@end

static CGFloat const SunPadTriggerDetentEnter = 0.75;
static CGFloat const SunPadTriggerDetentExit = 0.70;
static CGFloat const SunPadTriggerAnalogMinimum = 0.25;
static CGFloat const SunPadTriggerAnalogMaximum = 0.89;

static CGRect SunPadFrameAtNormalizedCenter(CGRect safe, CGFloat x, CGFloat y,
                                             CGFloat width, CGFloat height) {
    return CGRectMake(CGRectGetMinX(safe) + x * safe.size.width - width * 0.5,
                      CGRectGetMinY(safe) + y * safe.size.height - height * 0.5,
                      width, height);
}

// Keep the original persisted key names so layouts created while the D-pad
// grouping was experimental continue to work after grouping becomes standard.
static NSString *const SunPadExperimentalDPadOriginKey = @"SunPadExperimentalDPadOrigin";
static NSString *const SunPadExperimentalDPadScaleKey = @"SunPadExperimentalDPadScale";

static BOOL SunPadUsesPhoneLayoutDefaults(UIView *view) {
    return view.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone;
}

static CGFloat SunPadDefaultSizeScaleForControl(UIView *view, NSString *identifier) {
    return SunPadUsesPhoneLayoutDefaults(view) && [identifier isEqualToString:@"B"]
        ? 1.158457040786743
        : 1.0;
}

@interface SunPadTriggerButton : SunPadGameButton
@property(nonatomic, copy) void (^pressureChanged)(uint8_t pressure, BOOL fullPress);
- (void)resetState;
@end

@implementation SunPadTriggerButton {
    CAShapeLayer *_waterLayer;
    CAShapeLayer *_detentLayer;
    UIImpactFeedbackGenerator *_detentFeedback;
    CGFloat _pressure;
    BOOL _fullPress;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _waterLayer = [CAShapeLayer layer];
        _waterLayer.fillColor =
            [UIColor colorWithRed:0.10 green:0.67 blue:0.92 alpha:0.72].CGColor;
        [self.layer insertSublayer:_waterLayer atIndex:0];

        _detentLayer = [CAShapeLayer layer];
        _detentLayer.fillColor = UIColor.clearColor.CGColor;
        _detentLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.48].CGColor;
        _detentLayer.lineWidth = 1.5;
        [self.layer insertSublayer:_detentLayer above:_waterLayer];
        self.layer.masksToBounds = YES;
        self.accessibilityHint =
            @"Touch farther right for more pressure. The final section is a full press.";
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _waterLayer.frame = self.bounds;
    _detentLayer.frame = self.bounds;
    [self updateDetentPath];
    [self updateWaterAnimated:NO];
}

- (void)updateDetentPath {
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat x = width * SunPadTriggerDetentEnter;
    CGFloat slant = MIN(7.0, height * 0.14);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(x - slant, 0.0)];
    [path addLineToPoint:CGPointMake(x + slant, height)];
    _detentLayer.path = path.CGPath;
}

- (UIBezierPath *)waterPath {
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    if (_pressure <= 0.0 || width <= 0.0 || height <= 0.0)
        return [UIBezierPath bezierPath];
    if (_pressure >= 1.0)
        return [UIBezierPath bezierPathWithRect:self.bounds];

    CGFloat x = width * _pressure;
    CGFloat slant = MIN(10.0, height * 0.18);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(0.0, 0.0)];
    [path addLineToPoint:CGPointMake(MAX(0.0, x - slant), 0.0)];
    [path addLineToPoint:CGPointMake(MIN(width, x + slant), height)];
    [path addLineToPoint:CGPointMake(0.0, height)];
    [path closePath];
    return path;
}

- (void)updateWaterAnimated:(BOOL)animated {
    UIBezierPath *waterPath = [self waterPath];
    CGPathRef newPath = waterPath.CGPath;
    CGPathRef visiblePath = ((CAShapeLayer *)_waterLayer.presentationLayer).path;
    if (visiblePath == nil)
        visiblePath = _waterLayer.path;

    [_waterLayer removeAllAnimations];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _waterLayer.path = newPath;
    _waterLayer.fillColor = (_fullPress ?
        [UIColor colorWithRed:0.08 green:0.76 blue:1.0 alpha:0.88] :
        [UIColor colorWithRed:0.10 green:0.67 blue:0.92 alpha:0.72]).CGColor;
    [CATransaction commit];

    if (animated && !UIAccessibilityIsReduceMotionEnabled() && visiblePath != nil) {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"path"];
        animation.fromValue = (__bridge id)visiblePath;
        animation.toValue = (__bridge id)newPath;
        animation.duration = 0.07;
        animation.timingFunction =
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [_waterLayer addAnimation:animation forKey:@"water-fill"];
    }

    self.accessibilityValue = _fullPress ? @"Full press" :
        [NSString stringWithFormat:@"%ld percent", (long)std::lround(_pressure * 100.0)];
    self.layer.borderColor = (_fullPress ?
        [UIColor colorWithRed:0.42 green:0.88 blue:1.0 alpha:1.0] :
        [UIColor colorWithWhite:1.0 alpha:0.68]).CGColor;
    self.layer.borderWidth = _fullPress ? 3.0 : 2.0;
}

- (void)updateFromTouch:(UITouch *)touch {
    CGFloat width = MAX(1.0, CGRectGetWidth(self.bounds));
    CGFloat position = std::clamp<CGFloat>([touch locationInView:self].x / width, 0.0, 1.0);
    BOOL wasFull = _fullPress;
    _fullPress = wasFull ? position >= SunPadTriggerDetentExit
                         : position >= SunPadTriggerDetentEnter;
    CGFloat analogRange = SunPadTriggerAnalogMaximum - SunPadTriggerAnalogMinimum;
    _pressure = _fullPress ? 1.0 :
        MIN(SunPadTriggerAnalogMaximum,
            SunPadTriggerAnalogMinimum +
                (position / SunPadTriggerDetentEnter) * analogRange);
    [self updateWaterAnimated:YES];

    if (_fullPress && !wasFull) {
        if (_detentFeedback == nil)
            _detentFeedback = [[UIImpactFeedbackGenerator alloc]
                initWithStyle:UIImpactFeedbackStyleLight];
        [_detentFeedback impactOccurred];
    }
    if (self.pressureChanged)
        self.pressureChanged((uint8_t)std::lround(_pressure * 255.0), _fullPress);
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _detentFeedback = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleLight];
    [_detentFeedback prepare];
    self.highlighted = YES;
    [self updateFromTouch:touch];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    // Returning YES keeps this control tracking when the finger drifts past
    // either edge. updateFromTouch clamps the position instead of cancelling
    // the spray while the player is also moving with another finger.
    [self updateFromTouch:touch];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    self.highlighted = NO;
    if (self.pressureChanged)
        self.pressureChanged(0, NO);
    [self resetState];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    self.highlighted = NO;
    if (self.pressureChanged)
        self.pressureChanged(0, NO);
    [self resetState];
}

- (void)resetState {
    _pressure = 0.0;
    _fullPress = NO;
    _detentFeedback = nil;
    self.accessibilityValue = @"0 percent";
    [self updateWaterAnimated:YES];
}

@end

@interface SunPadDPadEditorGroup : UIView
@end

@implementation SunPadDPadEditorGroup
@end

@interface SunPadPassThroughView : UIView
@end

@implementation SunPadPassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    for (UIView *view = hit; view != nil && view != self; view = view.superview) {
        if ([view isKindOfClass:UIControl.class])
            return hit;
    }
    return nil;
}
@end

@interface SunPadGameOverlay () <UIGestureRecognizerDelegate>
@end

@implementation SunPadGameOverlay {
    UIButton *_menuButton;          // the three-dot menu
    SunPadStickView *_moveStick;
    SunPadStickView *_cStick;
    SunPadTriggerButton *_rTriggerButton;
    SunPadDPadEditorGroup *_experimentalDPadGroup;
    NSMutableArray<SunPadGameButton *> *_buttons;
    NSMutableArray<UIGestureRecognizer *> *_editGestures;

    UIView *_settingsPanel;
    UISegmentedControl *_renderScaleControl;
    UISlider *_opacitySlider;
    UISlider *_sizeSlider;
    UISlider *_selectedSizeSlider;
    UISwitch *_hideControlsSwitch;
    UISwitch *_modernCStickSwitch;
    UISwitch *_invertCStickVerticalSwitch;
    UISwitch *_editLayoutSwitch;
    UIButton *_resetLayoutButton;
    UIView *_editorBar;
    UILabel *_editorHintLabel;
    __weak UIView *_selectedControl;

    SunPadInputState _touchState;
    BOOL _touchControlsHidden;
    BOOL _editingLayout;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = YES;
        [self buildMenuButton];
        [self buildTouchControls];
        [self buildSettingsPanel];
        [self applySettings];
        [self observeControllerConnection];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Three-dot menu

- (void)buildMenuButton {
    _menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImageSymbolConfiguration *symbol =
        [UIImageSymbolConfiguration configurationWithPointSize:19.0
                                                        weight:UIImageSymbolWeightBold];
    UIImage *ellipsis = [UIImage systemImageNamed:@"ellipsis" withConfiguration:symbol];
    [_menuButton setImage:ellipsis forState:UIControlStateNormal];
    _menuButton.accessibilityLabel = @"Menu";
    _menuButton.showsMenuAsPrimaryAction = YES;
    if (@available(iOS 15.0, *))
        _menuButton.changesSelectionAsPrimaryAction = NO;
    _menuButton.menu = [self buildMenu];

    UIButtonConfiguration *configuration =
        [UIButtonConfiguration plainButtonConfiguration];
    configuration.image = ellipsis;
    configuration.baseForegroundColor = UIColor.whiteColor;
    configuration.contentInsets = NSDirectionalEdgeInsetsZero;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;

    UIBackgroundConfiguration *background =
        [UIBackgroundConfiguration clearConfiguration];
    background.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.72];
    background.cornerRadius = 20.0;
    background.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.30];
    background.strokeWidth = 1.0;
    configuration.background = background;

    // Keep the primary-action menu transition on one circular appearance.
    // Otherwise iPadOS can synthesize a rectangular selected state while the
    // menu is being dismissed.
    _menuButton.automaticallyUpdatesConfiguration = NO;
    _menuButton.configuration = configuration;
    _menuButton.tintColor = UIColor.whiteColor;
    _menuButton.backgroundColor = UIColor.clearColor;
    _menuButton.layer.borderWidth = 0.0;
    [self addSubview:_menuButton];
}

- (UIMenu *)buildMenu {
    __weak SunPadGameOverlay *weakSelf = self;
    SunPadSettings *settings = [SunPadSettings sharedSettings];

    UIMenu *renderMenu = [UIMenu menuWithTitle:@"Render Resolution" children:@[
        [self renderAction:@"1× (Native)" scale:1],
        [self renderAction:@"2×" scale:2],
        [self renderAction:@"3×" scale:3],
        [self renderAction:@"4×" scale:4],
    ]];

    UIMenu *aspectMenu = [UIMenu menuWithTitle:@"Aspect Ratio" children:@[
        [self aspectRatioAction:@"Original 4:3 (Restart Required)"
                           mode:SunPadAspectRatioOriginal],
        [self aspectRatioAction:@"16:9 (Experimental, Restart Required)"
                           mode:SunPadAspectRatioWidescreen],
        [self aspectRatioAction:@"Fill Screen (Experimental, Restart Required)"
                           mode:SunPadAspectRatioFillScreen],
    ]];

    UIMenu *displayMenu = [UIMenu menuWithTitle:@"Display"
                                          image:[UIImage systemImageNamed:@"display"]
                                     identifier:nil
                                        options:0
                                       children:@[renderMenu, aspectMenu]];

    UIMenu *dataMenu = [UIMenu menuWithTitle:@"Game Data & Saves"
                                       image:[UIImage systemImageNamed:@"internaldrive"]
                                  identifier:nil
                                     options:0
                                    children:@[
        [UIAction actionWithTitle:@"Import or Reimport Game Data"
                            image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf.delegate gameOverlayRequestsGameDataChange:weakSelf];
        }],
        [UIAction actionWithTitle:@"Import from SunPad Folder"
                            image:[UIImage systemImageNamed:@"folder"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf.delegate gameOverlayRequestsGameDataFolderImport:weakSelf];
        }],
        [UIAction actionWithTitle:@"Import Dolphin Save (.gci)…"
                            image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf.delegate gameOverlayRequestsSaveImport:weakSelf];
        }],
        [UIAction actionWithTitle:@"Export Saves…"
                            image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf exportSaves];
        }],
        [UIAction actionWithTitle:@"Remove Stored Game Data"
                            image:[UIImage systemImageNamed:@"trash"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf confirmGameDataRemoval];
        }],
    ]];

    UIAction *fpsAction = [UIAction actionWithTitle:@"Show FPS Counter"
                                              image:[UIImage systemImageNamed:@"speedometer"]
                                         identifier:nil
                                            handler:^(__kindof UIAction *action) {
        (void)action;
        SunPadSettings *currentSettings = [SunPadSettings sharedSettings];
        currentSettings.showFPSCounter = !currentSettings.showFPSCounter;
        [currentSettings synchronize];
        [weakSelf refreshMenuButton];
    }];
    fpsAction.state = settings.showFPSCounter ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *sixtyFPSAction =
        [UIAction actionWithTitle:@"60 FPS Patch (Unstable, Restart Required)"
                            image:[UIImage systemImageNamed:@"speedometer"]
                       identifier:nil handler:^(__kindof UIAction *action) {
        (void)action;
        SunPadSettings *currentSettings = [SunPadSettings sharedSettings];
        currentSettings.experimental60FPS = !currentSettings.experimental60FPS;
        [currentSettings synchronize];
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        [weakSelf refreshMenuButton];

        NSString *message = currentSettings.experimental60FPS ?
            @"This patch is diagnostic only. It is not a performance boost and is known to be unsuitable for normal play. It can cause severe slowdown and game-timing, physics, animation, or audio problems. Close and reopen SunPad to enable it." :
            @"The supported original 30 FPS mode is selected. Close and reopen SunPad to apply it.";
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Restart Required"
                                                message:message
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [weakSelf.window.rootViewController presentViewController:alert
                                                         animated:YES
                                                       completion:nil];
    }];
    sixtyFPSAction.state = settings.experimental60FPS ?
        UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *performanceAction =
        [UIAction actionWithTitle:@"Reduced CPU Clock 90% (Unstable, Restart Required)"
                            image:[UIImage systemImageNamed:@"gauge.with.dots.needle.67percent"]
                       identifier:nil handler:^(__kindof UIAction *action) {
        (void)action;
        SunPadSettings *currentSettings = [SunPadSettings sharedSettings];
        currentSettings.experimentalPerformanceMode =
            !currentSettings.experimentalPerformanceMode;
        [currentSettings synchronize];
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        [weakSelf refreshMenuButton];

        NSString *message = currentSettings.experimentalPerformanceMode ?
            @"This diagnostic mode reduces the emulated CPU clock. It is not a speed boost and can make Sunshine much slower. Severe rendering corruption has been reported while it is enabled. Close and reopen SunPad to enable it." :
            @"The supported full CPU clock is selected. Close and reopen SunPad to apply it.";
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Restart Required"
                                                message:message
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [weakSelf.window.rootViewController presentViewController:alert
                                                         animated:YES
                                                       completion:nil];
    }];
    performanceAction.state = settings.experimentalPerformanceMode ?
        UIMenuElementStateOn : UIMenuElementStateOff;

    BOOL supportedModeSelected = !settings.experimentalPerformanceMode &&
        !settings.experimental60FPS;
    UIAction *supportedModeAction =
        [UIAction actionWithTitle:@"Use Supported 30 FPS Mode (Restart Required)"
                            image:[UIImage systemImageNamed:@"checkmark.shield"]
                       identifier:nil handler:^(__kindof UIAction *action) {
        (void)action;
        SunPadSettings *currentSettings = [SunPadSettings sharedSettings];
        BOOL changed = currentSettings.experimentalPerformanceMode ||
            currentSettings.experimental60FPS;
        currentSettings.experimentalPerformanceMode = NO;
        currentSettings.experimental60FPS = NO;
        [currentSettings synchronize];
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        [weakSelf refreshMenuButton];

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:changed ? @"Supported Mode Selected" : @"Supported Mode Active"
                             message:changed ?
                @"Full CPU clock and the original 30 FPS mode are selected. Close and reopen SunPad to apply them." :
                @"Full CPU clock and the original 30 FPS mode are already selected."
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [weakSelf.window.rootViewController presentViewController:alert
                                                         animated:YES
                                                       completion:nil];
    }];
    supportedModeAction.state = supportedModeSelected ?
        UIMenuElementStateOn : UIMenuElementStateOff;

    NSString *experimentsTitle = supportedModeSelected ?
        @"Unstable Experiments (Off)" : @"⚠︎ Unstable Experiments Enabled";
    UIMenu *experimentsMenu = [UIMenu menuWithTitle:experimentsTitle
                                              image:[UIImage systemImageNamed:@"exclamationmark.triangle"]
                                         identifier:nil
                                            options:UIMenuOptionsDisplayInline
                                           children:@[
        supportedModeAction,
        [UIMenu menuWithTitle:@"Diagnostic Options, Not for Normal Play"
                         image:[UIImage systemImageNamed:@"wrench.and.screwdriver"]
                    identifier:nil
                       options:0
                      children:@[performanceAction, sixtyFPSAction]],
    ]];

    UIAction *reportProblemAction =
        [UIAction actionWithTitle:@"Report a Problem…"
                            image:[UIImage systemImageNamed:@"exclamationmark.bubble"]
                       identifier:nil handler:^(__kindof UIAction *action) {
        (void)action;
        [weakSelf reportProblem];
    }];

    UIAction *rumbleAction =
        [UIAction actionWithTitle:@"Controller Rumble"
                            image:[UIImage systemImageNamed:@"waveform"]
                       identifier:nil handler:^(__kindof UIAction *action) {
        (void)action;
        SunPadSettings *currentSettings = [SunPadSettings sharedSettings];
        currentSettings.controllerRumble = !currentSettings.controllerRumble;
        [currentSettings synchronize];
        [SunPadControllerRumble sharedRumble].allowed = currentSettings.controllerRumble;
        [weakSelf refreshMenuButton];
    }];
    rumbleAction.state = [SunPadSettings sharedSettings].controllerRumble ?
        UIMenuElementStateOn : UIMenuElementStateOff;

    UIMenu *controlsMenu = [UIMenu menuWithTitle:@"Controls"
                                           image:[UIImage systemImageNamed:@"gamecontroller"]
                                      identifier:nil
                                         options:0
                                        children:@[
        [UIAction actionWithTitle:@"Controller Button Mapping…"
                            image:[UIImage systemImageNamed:@"gamecontroller"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf.delegate gameOverlayRequestsControllerMapping:weakSelf];
        }],
        [UIAction actionWithTitle:@"Touch Control Settings…"
                            image:[UIImage systemImageNamed:@"hand.draw"]
                       identifier:nil handler:^(__kindof UIAction *action) {
            (void)action;
            [weakSelf toggleSettingsPanel];
        }],
        rumbleAction,
    ]];

    return [UIMenu menuWithTitle:@"SunPad" children:@[
        displayMenu,
        fpsAction,
        experimentsMenu,
        controlsMenu,
        dataMenu,
        reportProblemAction,
    ]];
}

- (void)exportSaves {
    UIViewController *presenter = self.window.rootViewController;
    NSError *error = nil;
    NSArray<NSURL *> *saves = [self.delegate gameOverlayExportSaves:self error:&error];
    if (saves == nil) {
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"No Saves Exported"
                                                message:error.localizedDescription
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIActivityViewController *share =
        [[UIActivityViewController alloc] initWithActivityItems:saves
                                         applicationActivities:nil];
    UIPopoverPresentationController *popover = share.popoverPresentationController;
    popover.sourceView = _menuButton;
    popover.sourceRect = _menuButton.bounds;
    [presenter presentViewController:share animated:YES completion:nil];
}

- (void)reportProblem {
    UIViewController *presenter = self.window.rootViewController;
    UIAlertController *prompt =
        [UIAlertController alertControllerWithTitle:@"Report a Problem"
                                            message:@"Answer briefly and SunPad will add the technical details. If the problem is visual, take a screenshot first and attach it with the report on GitHub. The report never includes your game image, extracted files, saves, signing material, or controller inputs. GitHub reports and attachments are public."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"What went wrong?";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Area and what you were doing (optional)";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Every time, sometimes, once, or not sure?";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [prompt addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    __weak SunPadGameOverlay *weakSelf = self;
    [prompt addAction:[UIAlertAction actionWithTitle:@"Share Report…"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
        (void)action;
        [weakSelf createDiagnosticReportFromPrompt:prompt openGitHub:NO];
    }]];
    [prompt addAction:[UIAlertAction actionWithTitle:@"Report on GitHub"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
        (void)action;
        [weakSelf createDiagnosticReportFromPrompt:prompt openGitHub:YES];
    }]];
    prompt.preferredAction = prompt.actions.lastObject;
    [presenter presentViewController:prompt animated:YES completion:nil];
}

- (void)createDiagnosticReportFromPrompt:(UIAlertController *)prompt
                              openGitHub:(BOOL)openGitHub {
    NSString *problem = prompt.textFields.count > 0 ? prompt.textFields[0].text : @"";
    NSString *context = prompt.textFields.count > 1 ? prompt.textFields[1].text : @"";
    NSString *frequency = prompt.textFields.count > 2 ? prompt.textFields[2].text : @"";
    NSString *reportID = [NSString stringWithFormat:@"SP-%@",
        [[[NSUUID UUID] UUIDString] substringToIndex:8]];
    NSDictionary<NSString *, NSString *> *answers = @{
        @"problem": problem ?: @"",
        @"context": context ?: @"",
        @"frequency": frequency ?: @"",
    };
    NSString *technicalContext = [self.delegate gameOverlayDiagnosticContext:self];
    SunPadLog(@"diagnostic report requested id=%@ destination=%@",
              reportID, openGitHub ? @"github" : @"share-sheet");
    NSError *error = nil;
    NSURL *reportURL = SunPadDiagnosticsReportURL(
        reportID, answers, technicalContext, &error);
    UIViewController *presenter = self.window.rootViewController;
    if (reportURL == nil) {
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Diagnostic Report Unavailable"
                                                message:error.localizedDescription
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }

    if (openGitHub) {
        [self openGitHubReportWithID:reportID answers:answers];
        return;
    }

    UIActivityViewController *share =
        [[UIActivityViewController alloc] initWithActivityItems:@[reportURL]
                                         applicationActivities:nil];
    UIPopoverPresentationController *popover = share.popoverPresentationController;
    popover.sourceView = _menuButton;
    popover.sourceRect = _menuButton.bounds;
    [presenter presentViewController:share animated:YES completion:nil];
}

- (void)openGitHubReportWithID:(NSString *)reportID
                       answers:(NSDictionary<NSString *, NSString *> *)answers {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown";
    NSString *platform = self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad ?
        @"iPad" : @"iPhone";
    NSString *problem = answers[@"problem"].length > 0 ? answers[@"problem"] : @"SunPad problem";
    if (problem.length > 100)
        problem = [problem substringToIndex:100];
    NSURLComponents *components = [NSURLComponents
        componentsWithString:@"https://github.com/chrissotraidis/sunpad/issues/new"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"template" value:@"bug_report.yml"],
        [NSURLQueryItem queryItemWithName:@"title"
                                    value:[NSString stringWithFormat:@"[Bug]: %@", problem]],
        [NSURLQueryItem queryItemWithName:@"report-id" value:reportID],
        [NSURLQueryItem queryItemWithName:@"revision"
                                    value:[NSString stringWithFormat:@"%@ (build %@)", version, build]],
        [NSURLQueryItem queryItemWithName:@"platform" value:platform],
        [NSURLQueryItem queryItemWithName:@"performance-profile"
                                    value:[self.delegate gameOverlayPerformanceProfile:self]],
        [NSURLQueryItem queryItemWithName:@"summary" value:answers[@"problem"]],
        [NSURLQueryItem queryItemWithName:@"context" value:answers[@"context"]],
        [NSURLQueryItem queryItemWithName:@"frequency" value:answers[@"frequency"]],
    ];
    NSURL *url = components.URL;
    if (url == nil)
        return;
    [UIApplication.sharedApplication openURL:url options:@{}
                           completionHandler:^(BOOL success) {
        if (!success)
            SunPadLog(@"diagnostic github open failed id=%@", reportID);
    }];
}

- (UIAction *)aspectRatioAction:(NSString *)title mode:(SunPadAspectRatioMode)mode {
    __weak SunPadGameOverlay *weakSelf = self;
    UIAction *aspectAction = [UIAction actionWithTitle:title
                                                 image:nil
                                            identifier:nil
                                               handler:^(__kindof UIAction *action) {
        (void)action;
        [SunPadSettings sharedSettings].aspectRatioMode = mode;
        [[SunPadSettings sharedSettings] synchronize];
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        [weakSelf refreshMenuButton];

        NSString *message = mode == SunPadAspectRatioOriginal ?
            @"Original 4:3 is selected. Close and reopen SunPad to apply it." :
            @"The game-specific Sunshine widescreen correction is selected. Close and reopen SunPad to apply it.";
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Restart Required"
                                                message:message
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [weakSelf.window.rootViewController presentViewController:alert
                                                         animated:YES
                                                       completion:nil];
    }];
    aspectAction.state = [SunPadSettings sharedSettings].aspectRatioMode == mode ?
        UIMenuElementStateOn : UIMenuElementStateOff;
    return aspectAction;
}

- (UIAction *)renderAction:(NSString *)title scale:(NSInteger)scale {
    __weak SunPadGameOverlay *weakSelf = self;
    UIAction *renderAction = [UIAction actionWithTitle:title
                                                 image:nil
                                            identifier:nil
                                               handler:^(__kindof UIAction *action) {
        (void)action;
        [SunPadSettings sharedSettings].renderScale = scale;
        [[SunPadSettings sharedSettings] synchronize];
        [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        [weakSelf refreshMenuButton];
    }];
    renderAction.state = [SunPadSettings sharedSettings].renderScale == scale ?
        UIMenuElementStateOn : UIMenuElementStateOff;
    return renderAction;
}

- (void)refreshMenuButton {
    _menuButton.menu = [self buildMenu];
}

- (void)confirmGameDataRemoval {
    __weak SunPadGameOverlay *weakSelf = self;
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Remove Stored Game Data?"
                                            message:@"The retained game image and extracted game files will be removed now. Your save files and control settings are not affected."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        (void)action;
        [weakSelf.delegate gameOverlayRequestsGameDataRemoval:weakSelf];
    }]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Touch controls

- (void)buildTouchControls {
    _buttons = [NSMutableArray array];
    _editGestures = [NSMutableArray array];

    _moveStick = [self makeStick];
    _cStick = [self makeStick];
    _moveStick.accessibilityLabel = @"Move stick";
    _moveStick.accessibilityIdentifier = @"move";
    _cStick.accessibilityLabel = @"Camera stick";
    _cStick.accessibilityIdentifier = @"c";
    [_moveStick applyBaseColor:[UIColor colorWithWhite:0.13 alpha:0.86]
                    thumbColor:[UIColor colorWithWhite:0.58 alpha:0.94]];
    [_cStick applyBaseColor:[UIColor colorWithRed:0.91 green:0.66 blue:0.08 alpha:0.90]
                 thumbColor:[UIColor colorWithRed:1.00 green:0.84 blue:0.25 alpha:0.98]];
    [self addSubview:_moveStick];
    [self addSubview:_cStick];
    [self addEditGesturesToControl:_moveStick];
    [self addEditGesturesToControl:_cStick];

    [self addButton:@"A" mask:SunPadButtonA];
    [self addButton:@"B" mask:SunPadButtonB];
    [self addButton:@"X" mask:SunPadButtonX];
    [self addButton:@"Y" mask:SunPadButtonY];
    [self addButton:@"Z" mask:SunPadButtonZ];
    [self addButton:@"START" mask:SunPadButtonStart];
    [self addButton:@"L" mask:SunPadButtonL];
    [self addButton:@"R" mask:SunPadButtonR];
    // D-pad
    [self addButton:@"▲" mask:SunPadButtonDpadUp];
    [self addButton:@"▼" mask:SunPadButtonDpadDown];
    [self addButton:@"◀" mask:SunPadButtonDpadLeft];
    [self addButton:@"▶" mask:SunPadButtonDpadRight];

    _experimentalDPadGroup = [SunPadDPadEditorGroup new];
    _experimentalDPadGroup.accessibilityLabel = @"D-pad";
    _experimentalDPadGroup.accessibilityIdentifier = @"ExperimentalDPad";
    _experimentalDPadGroup.backgroundColor = UIColor.clearColor;
    _experimentalDPadGroup.layer.cornerRadius = 14.0;
    _experimentalDPadGroup.hidden = YES;
    _experimentalDPadGroup.userInteractionEnabled = NO;
    [self addSubview:_experimentalDPadGroup];
    [self addEditGesturesToControl:_experimentalDPadGroup];
}

- (SunPadStickView *)makeStick {
    SunPadStickView *stick = [[SunPadStickView alloc] initWithFrame:CGRectMake(0, 0, 128, 128)];
    __weak SunPadGameOverlay *weakSelf = self;
    __weak SunPadStickView *weakStick = stick;
    stick.valueChanged = ^(float x, float y) {
        SunPadStickView *strongStick = weakStick;
        if (strongStick != nil)
            [weakSelf stickChanged:strongStick x:x y:y];
    };
    return stick;
}

- (void)addButton:(NSString *)label mask:(uint16_t)mask {
    SunPadGameButton *button = mask == SunPadButtonR ?
        [SunPadTriggerButton buttonWithType:UIButtonTypeSystem] :
        [SunPadGameButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:label forState:UIControlStateNormal];
    UIColor *fill = [UIColor colorWithWhite:0.22 alpha:0.88];
    UIColor *titleColor = UIColor.whiteColor;
    switch (mask) {
    case SunPadButtonA:
        fill = [UIColor colorWithRed:0.08 green:0.56 blue:0.29 alpha:0.92];
        break;
    case SunPadButtonB:
        fill = [UIColor colorWithRed:0.78 green:0.10 blue:0.13 alpha:0.92];
        break;
    case SunPadButtonX:
    case SunPadButtonY:
        fill = [UIColor colorWithWhite:0.72 alpha:0.92];
        titleColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        break;
    case SunPadButtonZ:
        fill = [UIColor colorWithRed:0.38 green:0.18 blue:0.58 alpha:0.94];
        break;
    case SunPadButtonStart:
        fill = [UIColor colorWithWhite:0.28 alpha:0.92];
        break;
    default:
        break;
    }
    [button setTitleColor:titleColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    button.backgroundColor = fill;
    button.layer.cornerRadius = 28.0;
    button.layer.borderWidth = 2.0;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.36].CGColor;
    button.accessibilityLabel = label;
    button.inputMask = mask;
    button.accessibilityIdentifier = [self identifierForMask:mask];
    [button addTarget:self action:@selector(buttonDown:)
     forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(buttonUp:)
     forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                            UIControlEventTouchCancel];
    [_buttons addObject:button];
    [self addSubview:button];
    [self addEditGesturesToControl:button];

    if (mask == SunPadButtonR) {
        _rTriggerButton = (SunPadTriggerButton *)button;
        __weak SunPadGameOverlay *weakSelf = self;
        _rTriggerButton.pressureChanged = ^(uint8_t pressure, BOOL fullPress) {
            [weakSelf rPressureChanged:pressure fullPress:fullPress];
        };
    }
}

- (void)stickChanged:(SunPadStickView *)stick x:(float)x y:(float)y {
    if (_editingLayout)
        return;
    int8_t xi = (int8_t)std::lround(x * 127.0f);
    int8_t yi = (int8_t)std::lround(y * 127.0f);
    if (stick == _moveStick) {
        _touchState.stickX = xi;
        _touchState.stickY = yi;
    } else {
        _touchState.cStickX = xi;
        _touchState.cStickY = yi;
    }
    _touchState.connected = 1;
    [[SunPadInputMixer sharedMixer] setInputState:_touchState fromTouch:YES];
}

- (void)buttonDown:(SunPadGameButton *)button {
    if (_editingLayout)
        return;
    if (button.inputMask == SunPadButtonR)
        return;
    _touchState.buttons |= button.inputMask;
    if (button.inputMask == SunPadButtonL)
        _touchState.triggerL = 255;
    if (button.inputMask == SunPadButtonR)
        _touchState.triggerR = 255;
    button.transform = CGAffineTransformMakeScale(0.92, 0.92);
    _touchState.connected = 1;
    [[SunPadInputMixer sharedMixer] setInputState:_touchState fromTouch:YES];
}

- (void)buttonUp:(SunPadGameButton *)button {
    if (_editingLayout)
        return;
    if (button.inputMask == SunPadButtonR)
        return;
    _touchState.buttons &= ~button.inputMask;
    if (button.inputMask == SunPadButtonL)
        _touchState.triggerL = 0;
    if (button.inputMask == SunPadButtonR)
        _touchState.triggerR = 0;
    button.transform = CGAffineTransformIdentity;
    _touchState.connected = 1;
    [[SunPadInputMixer sharedMixer] setInputState:_touchState fromTouch:YES];
}

- (void)rPressureChanged:(uint8_t)pressure fullPress:(BOOL)fullPress {
    if (_editingLayout)
        return;
    _touchState.triggerR = pressure;
    if (fullPress)
        _touchState.buttons |= SunPadButtonR;
    else
        _touchState.buttons &= ~SunPadButtonR;
    _touchState.connected = 1;
    [[SunPadInputMixer sharedMixer] setInputState:_touchState fromTouch:YES];
}

- (void)clearTouchInput {
    for (SunPadGameButton *button in _buttons)
        button.transform = CGAffineTransformIdentity;
    [_moveStick reset];
    [_cStick reset];
    [_rTriggerButton resetState];
    _touchState = {};
    [[SunPadInputMixer sharedMixer] clearInputFromTouch:YES];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = self.bounds;
    if (@available(iOS 11.0, *)) {
        safe = UIEdgeInsetsInsetRect(safe, self.safeAreaInsets);
    }
    // BellPad's landscape layout math: scale to a reference 800x380 area on
    // phones and a fixed larger set on iPads (width >= 1000).
    BOOL pad = self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad &&
               safe.size.width >= 1000.0;
    BOOL phone = SunPadUsesPhoneLayoutDefaults(self);
    CGFloat baseScale = pad ? 1.0
                            : std::min<CGFloat>(1.0, std::min(safe.size.width / 800.0,
                                                              safe.size.height / 380.0));
    CGFloat controlScale = [SunPadSettings sharedSettings].controlSizeScale;
    CGFloat scale = baseScale * controlScale;
    CGFloat margin = pad ? 34.0 : std::max<CGFloat>(8.0, 18.0 * baseScale);
    CGFloat stick = (pad ? 172.0 : 126.0 * baseScale) * controlScale;
    CGFloat small = (pad ? 62.0 : 46.0 * baseScale) * controlScale;
    CGFloat medium = (pad ? 76.0 : 58.0 * baseScale) * controlScale;
    CGFloat large = (pad ? 104.0 : 78.0 * baseScale) * controlScale;

    CGRect moveDefault = phone ?
        SunPadFrameAtNormalizedCenter(safe, 0.1234722222, 0.7803490991, stick, stick) : pad ?
        SunPadFrameAtNormalizedCenter(safe, 0.1310395315, 0.7905894519, stick, stick) :
        CGRectMake(CGRectGetMinX(safe) + margin,
                   CGRectGetMaxY(safe) - stick - margin, stick, stick);
    [self placeControl:_moveStick
          defaultFrame:moveDefault
            identifier:@"move"];
    CGFloat camera = (pad ? 112.0 : 86.0 * baseScale) * controlScale;
    CGRect cameraDefault = phone ?
        SunPadFrameAtNormalizedCenter(safe, 0.9233055556, 0.8130067568, camera, camera) : pad ?
        SunPadFrameAtNormalizedCenter(safe, 0.9062957540, 0.8583247156, camera, camera) :
        CGRectMake(CGRectGetMaxX(safe) - margin - camera,
                   CGRectGetMaxY(safe) - margin - camera, camera, camera);
    [self placeControl:_cStick
          defaultFrame:cameraDefault
            identifier:@"c"];

    SunPadGameButton *a = [self buttonWithMask:SunPadButtonA];
    SunPadGameButton *b = [self buttonWithMask:SunPadButtonB];
    SunPadGameButton *x = [self buttonWithMask:SunPadButtonX];
    SunPadGameButton *y = [self buttonWithMask:SunPadButtonY];
    // A was not present in the captured iPhone preferences because it was not
    // moved. Keep the original phone fallback so the sparse captured layout
    // reconstructs the exact arrangement the user made.
    CGRect aDefault = pad ?
        SunPadFrameAtNormalizedCenter(safe, 0.8916544656, 0.7409513961, large, large) :
        CGRectMake(CGRectGetMaxX(safe) - margin - large,
                   CGRectGetMaxY(safe) - margin - camera - large - 18.0 * scale,
                   large, large);
    [self placeControl:a
          defaultFrame:aDefault
            identifier:@"A"];
    CGRect bDefault = phone ?
        SunPadFrameAtNormalizedCenter(safe, 0.8398611111, 0.6898648649, medium, medium) : pad ?
        SunPadFrameAtNormalizedCenter(safe, 0.8360175695, 0.8092037229, medium, medium) :
        CGRectMake(CGRectGetMinX(a.frame) - medium - 12.0 * scale,
                   CGRectGetMidY(a.frame) + 8.0, medium, medium);
    [self placeControl:b
          defaultFrame:bDefault
            identifier:@"B"];
    CGRect xDefault = phone ?
        SunPadFrameAtNormalizedCenter(safe, 0.9034166667, 0.4258445946, small, small) : pad ?
        SunPadFrameAtNormalizedCenter(safe, 0.9593704246, 0.7156153051, small, small) :
        CGRectMake(CGRectGetMidX(a.frame) - small * 0.5,
                   CGRectGetMinY(a.frame) - small - 10.0 * scale, small, small);
    [self placeControl:x
          defaultFrame:xDefault
            identifier:@"X"];
    CGRect yDefault = phone ?
        SunPadFrameAtNormalizedCenter(safe, 0.8452500000, 0.5268581081, small, small) : pad ?
        SunPadFrameAtNormalizedCenter(safe, 0.9542459736, 0.7869700103, small, small) :
        CGRectMake(CGRectGetMinX(a.frame) - small - 8.0 * scale,
                   CGRectGetMinY(a.frame) - small + 8.0, small, small);
    [self placeControl:y
          defaultFrame:yDefault
            identifier:@"Y"];

    CGFloat shoulderWidth = (pad ? 132.0 : 94.0 * baseScale) * controlScale;
    CGFloat shoulderY = CGRectGetMinY(safe) + (pad ? 92.0 : 68.0 * baseScale);
    CGRect lDefault = phone ?
        SunPadFrameAtNormalizedCenter(safe, 0.0905833333, 0.2539977477,
                                      shoulderWidth, small) : pad ?
        SunPadFrameAtNormalizedCenter(safe, 0.1281112738, 0.6633919338,
                                      shoulderWidth, small) :
        CGRectMake(CGRectGetMinX(safe) + margin, shoulderY, shoulderWidth, small);
    [self placeControl:[self buttonWithMask:SunPadButtonL]
          defaultFrame:lDefault
            identifier:@"L"];
    CGFloat rightShoulderWidth = shoulderWidth + 2.0 * small + 24.0 * scale;
    SunPadGameButton *rightShoulder = [self buttonWithMask:SunPadButtonR];
    CGRect rDefault = phone ?
        SunPadFrameAtNormalizedCenter(safe, 0.8687500000, 0.2729166667,
                                      rightShoulderWidth, small) : pad ?
        SunPadFrameAtNormalizedCenter(safe, 0.8960468521, 0.6478800414,
                                      rightShoulderWidth, small) :
        CGRectMake(CGRectGetMaxX(safe) - margin - rightShoulderWidth, shoulderY,
                   rightShoulderWidth, small);
    [self placeControl:rightShoulder
          defaultFrame:rDefault
            identifier:@"R"];
    CGRect zDefault = phone ?
        SunPadFrameAtNormalizedCenter(safe, 0.9712500000, 0.4350788288, small, small) : pad ?
        SunPadFrameAtNormalizedCenter(safe, 0.8275988287, 0.7213029990, small, small) :
        CGRectMake(CGRectGetMaxX(safe) - margin - shoulderWidth - small - 12.0 * scale,
                   shoulderY, small, small);
    [self placeControl:[self buttonWithMask:SunPadButtonZ]
          defaultFrame:zDefault
            identifier:@"Z"];
    CGFloat startWidth = (pad ? 116.0 : 92.0 * baseScale) * controlScale;
    CGRect startDefault = phone ?
        SunPadFrameAtNormalizedCenter(safe, 0.0902222222, 0.1128941441,
                                      startWidth, small) : pad ?
        SunPadFrameAtNormalizedCenter(safe, 0.8967789165, 0.5780765253,
                                      startWidth, small) :
        CGRectMake(CGRectGetMidX(safe) - startWidth * 0.5,
                   CGRectGetMinY(safe) + margin, startWidth, small);
    [self placeControl:[self buttonWithMask:SunPadButtonStart]
          defaultFrame:startDefault
            identifier:@"Start"];

    CGFloat d = (pad ? 48.0 : 36.0 * baseScale) * controlScale;
    CGFloat dx = CGRectGetMaxX(_moveStick.frame) + (pad ? 34.0 : 18.0 * scale);
    CGRect defaultGroupFrame = phone ?
        SunPadFrameAtNormalizedCenter(safe, 0.0812777778, 0.4677364865,
                                      3.0 * d, 3.0 * d) : pad ?
        SunPadFrameAtNormalizedCenter(safe, 0.2686676428, 0.7947259566,
                                      3.0 * d, 3.0 * d) :
        CGRectMake(dx, CGRectGetMidY(_moveStick.frame) - 1.5 * d, 3.0 * d, 3.0 * d);
    [self placeExperimentalDPadGroupWithDefaultFrame:defaultGroupFrame safeArea:safe];
    [self layoutExperimentalDPadButtons];

    for (SunPadGameButton *button in _buttons) {
        button.layer.cornerRadius =
            std::min(button.bounds.size.width, button.bounds.size.height) * 0.5;
    }

    CGFloat settingsSide = 40.0;
    CGFloat menuInset = 12.0;
    _menuButton.frame = CGRectMake(CGRectGetMaxX(safe) - settingsSide - menuInset,
                                   CGRectGetMinY(safe) + menuInset,
                                   settingsSide, settingsSide);

    [self layoutSettingsPanelInSafeArea:safe];
    CGFloat editorWidth = MIN(560.0, CGRectGetWidth(safe) - 24.0);
    CGFloat editorHeight = 60.0;
    _editorBar.frame = CGRectMake(CGRectGetMidX(safe) - editorWidth * 0.5,
                                  CGRectGetMaxY(safe) - editorHeight - 12.0,
                                  editorWidth, editorHeight);
    [self updateControlAppearance];
    if (!_settingsPanel.hidden)
        [self bringSubviewToFront:_settingsPanel];
    if (!_editorBar.hidden)
        [self bringSubviewToFront:_editorBar];
    [self bringSubviewToFront:_menuButton];
}

- (CGFloat)experimentalDPadScale {
    NSNumber *saved = [[NSUserDefaults standardUserDefaults]
        objectForKey:SunPadExperimentalDPadScaleKey];
    return saved == nil ? 1.0 : std::clamp<CGFloat>(saved.doubleValue, 0.60, 1.75);
}

- (void)placeExperimentalDPadGroupWithDefaultFrame:(CGRect)defaultFrame safeArea:(CGRect)safe {
    CGFloat individualScale = [self experimentalDPadScale];
    _experimentalDPadGroup.bounds = CGRectMake(0, 0,
        defaultFrame.size.width * individualScale,
        defaultFrame.size.height * individualScale);

    NSString *savedPoint = [[NSUserDefaults standardUserDefaults]
        stringForKey:SunPadExperimentalDPadOriginKey];
    CGPoint center = savedPoint.length > 0 ? CGPointFromString(savedPoint) : CGPointMake(-1.0, -1.0);
    if (center.x >= 0.0 && center.y >= 0.0) {
        center.x = CGRectGetMinX(safe) + std::clamp<CGFloat>(center.x, 0.0, 1.0) * safe.size.width;
        center.y = CGRectGetMinY(safe) + std::clamp<CGFloat>(center.y, 0.0, 1.0) * safe.size.height;
    } else {
        center = CGPointMake(CGRectGetMidX(defaultFrame), CGRectGetMidY(defaultFrame));
    }
    CGFloat halfWidth = MIN(_experimentalDPadGroup.bounds.size.width * 0.5,
                            safe.size.width * 0.5);
    CGFloat halfHeight = MIN(_experimentalDPadGroup.bounds.size.height * 0.5,
                             safe.size.height * 0.5);
    center.x = std::clamp(center.x, CGRectGetMinX(safe) + halfWidth,
                         CGRectGetMaxX(safe) - halfWidth);
    center.y = std::clamp(center.y, CGRectGetMinY(safe) + halfHeight,
                         CGRectGetMaxY(safe) - halfHeight);
    _experimentalDPadGroup.center = center;
}

- (void)layoutExperimentalDPadButtons {
    CGFloat cell = _experimentalDPadGroup.bounds.size.width / 3.0;
    CGPoint center = _experimentalDPadGroup.center;
    struct {
        uint16_t mask;
        CGFloat x, y;
    } placements[] = {
        {SunPadButtonDpadUp, 0.0, -1.0},
        {SunPadButtonDpadDown, 0.0, 1.0},
        {SunPadButtonDpadLeft, -1.0, 0.0},
        {SunPadButtonDpadRight, 1.0, 0.0},
    };
    for (const auto &placement : placements) {
        SunPadGameButton *button = [self buttonWithMask:placement.mask];
        button.bounds = CGRectMake(0, 0, cell, cell);
        button.center = CGPointMake(center.x + placement.x * cell,
                                    center.y + placement.y * cell);
    }
}

- (void)placeControl:(UIView *)control defaultFrame:(CGRect)defaultFrame identifier:(NSString *)identifier {
    NSDictionary *savedScales = [[NSUserDefaults standardUserDefaults]
        dictionaryForKey:@"SunPadControlSizeScales"];
    CGFloat individualScale = savedScales[identifier] != nil
        ? [[SunPadSettings sharedSettings] sizeScaleForControl:identifier]
        : SunPadDefaultSizeScaleForControl(self, identifier);
    control.bounds = CGRectMake(0, 0, defaultFrame.size.width * individualScale,
                                defaultFrame.size.height * individualScale);
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults]
        dictionaryForKey:@"SunPadControlOrigins"];
    id savedPoint = saved[identifier];
    if (savedPoint != nil) {
        CGPoint normalized = CGPointZero;
        if ([savedPoint isKindOfClass:NSString.class])
            normalized = CGPointFromString(savedPoint);
        else if ([savedPoint isKindOfClass:NSValue.class])
            normalized = [savedPoint CGPointValue];
        normalized.x = std::clamp<CGFloat>(normalized.x, 0.0, 1.0);
        normalized.y = std::clamp<CGFloat>(normalized.y, 0.0, 1.0);
        CGRect safe = self.bounds;
        if (@available(iOS 11.0, *))
            safe = UIEdgeInsetsInsetRect(safe, self.safeAreaInsets);
        CGFloat cx = CGRectGetMinX(safe) + normalized.x * safe.size.width;
        CGFloat cy = CGRectGetMinY(safe) + normalized.y * safe.size.height;
        CGFloat halfW = control.bounds.size.width * 0.5;
        CGFloat halfH = control.bounds.size.height * 0.5;
        cx = std::clamp(cx, CGRectGetMinX(safe) + halfW, CGRectGetMaxX(safe) - halfW);
        cy = std::clamp(cy, CGRectGetMinY(safe) + halfH, CGRectGetMaxY(safe) - halfH);
        control.center = CGPointMake(cx, cy);
    } else {
        control.center = CGPointMake(CGRectGetMidX(defaultFrame), CGRectGetMidY(defaultFrame));
    }
}

- (SunPadGameButton *)buttonWithMask:(uint16_t)mask {
    for (SunPadGameButton *button in _buttons) {
        if (button.inputMask == mask)
            return button;
    }
    return nil;
}

- (void)layoutSettingsPanelInSafeArea:(CGRect)safe {
    CGFloat width = MIN(360.0, CGRectGetWidth(safe) - 32.0);
    CGFloat height = MIN(430.0, CGRectGetHeight(safe) * 0.62);
    _settingsPanel.frame = CGRectMake(CGRectGetMaxX(safe) - width - 12.0,
                                      CGRectGetMinY(safe) + 60.0,
                                      width, height);
}

#pragma mark - Settings panel

- (void)buildSettingsPanel {
    _settingsPanel = [UIView new];
    _settingsPanel.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.94];
    _settingsPanel.layer.cornerRadius = 16.0;
    _settingsPanel.layer.borderWidth = 1.0;
    _settingsPanel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    _settingsPanel.hidden = YES;
    [self addSubview:_settingsPanel];

    UILabel *title = [UILabel new];
    title.text = @"Touch Control Settings";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImageSymbolConfiguration *closeSymbol =
        [UIImageSymbolConfiguration configurationWithPointSize:16.0
                                                        weight:UIImageSymbolWeightBold];
    [close setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:closeSymbol]
           forState:UIControlStateNormal];
    close.tintColor = UIColor.whiteColor;
    close.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
    close.layer.cornerRadius = 16.0;
    close.accessibilityLabel = @"Close touch control settings";
    [close addTarget:self action:@selector(closeSettingsPanel)
      forControlEvents:UIControlEventTouchUpInside];

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[title, close]];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.axis = UILayoutConstraintAxisHorizontal;
    header.alignment = UIStackViewAlignmentCenter;
    header.spacing = 12.0;
    [_settingsPanel addSubview:header];

    _renderScaleControl = [[UISegmentedControl alloc] initWithItems:@[@"1×", @"2×", @"3×", @"4×"]];
    _renderScaleControl.selectedSegmentIndex = [SunPadSettings sharedSettings].renderScale - 1;
    _renderScaleControl.accessibilityLabel = @"Render resolution";
    [_renderScaleControl addTarget:self action:@selector(renderScaleChanged:)
                  forControlEvents:UIControlEventValueChanged];

    _opacitySlider = [UISlider new];
    _opacitySlider.minimumValue = 0.25;
    _opacitySlider.maximumValue = 1.0;
    _opacitySlider.value = [SunPadSettings sharedSettings].controlOpacity;
    _opacitySlider.accessibilityLabel = @"Control opacity";
    [_opacitySlider addTarget:self action:@selector(opacityChanged:)
             forControlEvents:UIControlEventValueChanged];

    _sizeSlider = [UISlider new];
    _sizeSlider.minimumValue = 0.70;
    _sizeSlider.maximumValue = 1.35;
    _sizeSlider.value = [SunPadSettings sharedSettings].controlSizeScale;
    _sizeSlider.accessibilityLabel = @"Control size";
    [_sizeSlider addTarget:self action:@selector(sizeChanged:)
          forControlEvents:UIControlEventValueChanged];

    _selectedSizeSlider = [UISlider new];
    _selectedSizeSlider.minimumValue = 0.60;
    _selectedSizeSlider.maximumValue = 1.75;
    _selectedSizeSlider.value = 1.0;
    _selectedSizeSlider.enabled = NO;
    _selectedSizeSlider.accessibilityLabel = @"Selected control size";
    [_selectedSizeSlider addTarget:self action:@selector(selectedSizeChanged:)
                   forControlEvents:UIControlEventValueChanged];

    _hideControlsSwitch = [UISwitch new];
    _hideControlsSwitch.on = [SunPadSettings sharedSettings].hideTouchControlsWhenControllerConnected;
    _hideControlsSwitch.accessibilityLabel = @"Hide touch controls when controller connected";
    [_hideControlsSwitch addTarget:self action:@selector(hideChanged:)
                  forControlEvents:UIControlEventValueChanged];

    _modernCStickSwitch = [UISwitch new];
    _modernCStickSwitch.on = [SunPadSettings sharedSettings].modernCStickHorizontal;
    _modernCStickSwitch.accessibilityLabel = @"Modern C-stick left and right";
    [_modernCStickSwitch addTarget:self action:@selector(modernCStickChanged:)
                   forControlEvents:UIControlEventValueChanged];

    _invertCStickVerticalSwitch = [UISwitch new];
    _invertCStickVerticalSwitch.on = [SunPadSettings sharedSettings].invertCStickVertical;
    _invertCStickVerticalSwitch.accessibilityLabel = @"Invert C-stick up and down";
    [_invertCStickVerticalSwitch addTarget:self action:@selector(invertCStickVerticalChanged:)
                          forControlEvents:UIControlEventValueChanged];

    _editLayoutSwitch = [UISwitch new];
    _editLayoutSwitch.on = NO;
    _editLayoutSwitch.accessibilityLabel = @"Move touch controls";
    [_editLayoutSwitch addTarget:self action:@selector(editLayoutChanged:)
                forControlEvents:UIControlEventValueChanged];

    _resetLayoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_resetLayoutButton setTitle:@"Reset This Device Layout" forState:UIControlStateNormal];
    [_resetLayoutButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _resetLayoutButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    _resetLayoutButton.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.88];
    _resetLayoutButton.layer.cornerRadius = 10.0;
    [_resetLayoutButton addTarget:self action:@selector(confirmResetLayout)
    forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self settingsRowWithTitle:@"Render" control:_renderScaleControl],
        [self settingsRowWithTitle:@"Opacity" control:_opacitySlider],
        [self settingsRowWithTitle:@"All sizes" control:_sizeSlider],
        [self settingsRowWithTitle:@"Hide on controller" control:_hideControlsSwitch],
        [self settingsRowWithTitle:@"Modern C-stick L/R" control:_modernCStickSwitch],
        [self settingsRowWithTitle:@"Invert C-stick Up/Down" control:_invertCStickVerticalSwitch],
        [self settingsRowWithTitle:@"Move controls" control:_editLayoutSwitch],
        _resetLayoutButton,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6.0;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = NO;
    scroll.showsVerticalScrollIndicator = YES;
    [_settingsPanel addSubview:scroll];
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:_settingsPanel.leadingAnchor constant:16.0],
        [header.trailingAnchor constraintEqualToAnchor:_settingsPanel.trailingAnchor constant:-12.0],
        [header.topAnchor constraintEqualToAnchor:_settingsPanel.topAnchor constant:8.0],
        [header.heightAnchor constraintEqualToConstant:40.0],
        [close.widthAnchor constraintEqualToConstant:32.0],
        [close.heightAnchor constraintEqualToConstant:32.0],
        [scroll.leadingAnchor constraintEqualToAnchor:_settingsPanel.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:_settingsPanel.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:2.0],
        [scroll.bottomAnchor constraintEqualToAnchor:_settingsPanel.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8.0],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-8.0],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32.0],
        [_resetLayoutButton.heightAnchor constraintEqualToConstant:40.0],
    ]];

    _editorBar = [SunPadPassThroughView new];
    _editorBar.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.95];
    _editorBar.layer.cornerRadius = 16.0;
    _editorBar.layer.borderWidth = 1.0;
    _editorBar.layer.borderColor =
        [UIColor colorWithRed:1.0 green:0.78 blue:0.20 alpha:0.95].CGColor;
    _editorBar.hidden = YES;
    [self addSubview:_editorBar];

    _editorHintLabel = [UILabel new];
    _editorHintLabel.text = @"Drag controls • tap one to resize";
    _editorHintLabel.textColor = UIColor.whiteColor;
    _editorHintLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    _editorHintLabel.adjustsFontSizeToFitWidth = YES;
    _editorHintLabel.minimumScaleFactor = 0.75;

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    [done setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    done.backgroundColor = [UIColor colorWithRed:0.12 green:0.48 blue:0.82 alpha:1.0];
    done.layer.cornerRadius = 10.0;
    done.accessibilityLabel = @"Finish moving touch controls";
    [done addTarget:self action:@selector(finishLayoutEditing)
      forControlEvents:UIControlEventTouchUpInside];

    UIStackView *editorStack = [[UIStackView alloc]
        initWithArrangedSubviews:@[_editorHintLabel, _selectedSizeSlider, done]];
    editorStack.translatesAutoresizingMaskIntoConstraints = NO;
    editorStack.axis = UILayoutConstraintAxisHorizontal;
    editorStack.alignment = UIStackViewAlignmentCenter;
    editorStack.spacing = 12.0;
    [_editorBar addSubview:editorStack];
    [_editorHintLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                     forAxis:UILayoutConstraintAxisHorizontal];
    [_selectedSizeSlider setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh
                                                         forAxis:UILayoutConstraintAxisHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [editorStack.leadingAnchor constraintEqualToAnchor:_editorBar.leadingAnchor constant:14.0],
        [editorStack.trailingAnchor constraintEqualToAnchor:_editorBar.trailingAnchor constant:-10.0],
        [editorStack.topAnchor constraintEqualToAnchor:_editorBar.topAnchor constant:8.0],
        [editorStack.bottomAnchor constraintEqualToAnchor:_editorBar.bottomAnchor constant:-8.0],
        [_selectedSizeSlider.widthAnchor constraintGreaterThanOrEqualToConstant:150.0],
        [done.widthAnchor constraintEqualToConstant:68.0],
        [done.heightAnchor constraintEqualToConstant:40.0],
    ]];
}

- (UIView *)settingsRowWithTitle:(NSString *)title control:(UIView *)control {
    UILabel *label = [UILabel new];
    label.text = title;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    [control setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12.0;
    row.alignment = UIStackViewAlignmentCenter;
    return row;
}

- (void)toggleSettingsPanel {
    if (_editingLayout)
        [self finishLayoutEditing];
    if (_settingsPanel.hidden) {
        _settingsPanel.hidden = NO;
        _renderScaleControl.selectedSegmentIndex = [SunPadSettings sharedSettings].renderScale - 1;
        _modernCStickSwitch.on = [SunPadSettings sharedSettings].modernCStickHorizontal;
        _invertCStickVerticalSwitch.on = [SunPadSettings sharedSettings].invertCStickVertical;
        [self bringSubviewToFront:_settingsPanel];
        [self bringSubviewToFront:_menuButton];
    } else {
        [self closeSettingsPanel];
    }
}

- (void)closeSettingsPanel {
    _settingsPanel.hidden = YES;
    if (_editingLayout)
        [self finishLayoutEditing];
}

- (void)renderScaleChanged:(UISegmentedControl *)control {
    [SunPadSettings sharedSettings].renderScale = control.selectedSegmentIndex + 1;
    [[SunPadSettings sharedSettings] synchronize];
    [self refreshMenuButton];
}

- (void)opacityChanged:(UISlider *)slider {
    [SunPadSettings sharedSettings].controlOpacity = slider.value;
    [[SunPadSettings sharedSettings] synchronize];
    [self setNeedsLayout];
}

- (void)sizeChanged:(UISlider *)slider {
    [SunPadSettings sharedSettings].controlSizeScale = slider.value;
    [[SunPadSettings sharedSettings] synchronize];
    [self setNeedsLayout];
}

- (void)hideChanged:(UISwitch *)switcher {
    [SunPadSettings sharedSettings].hideTouchControlsWhenControllerConnected = switcher.on;
    [[SunPadSettings sharedSettings] synchronize];
    [self applyControllerVisibility];
}

- (void)modernCStickChanged:(UISwitch *)switcher {
    [SunPadSettings sharedSettings].modernCStickHorizontal = switcher.on;
    [[SunPadSettings sharedSettings] synchronize];
}

- (void)invertCStickVerticalChanged:(UISwitch *)switcher {
    [SunPadSettings sharedSettings].invertCStickVertical = switcher.on;
    [[SunPadSettings sharedSettings] synchronize];
}

- (void)editLayoutChanged:(UISwitch *)switcher {
    if (switcher.on)
        [self beginLayoutEditing];
    else
        [self endLayoutEditing];
}

- (void)finishLayoutEditing {
    _editLayoutSwitch.on = NO;
    [self endLayoutEditing];
}

- (void)confirmResetLayout {
    __weak SunPadGameOverlay *weakSelf = self;
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Reset Touch Control Layout?"
                                            message:@"All control positions and sizes, including the grouped D-pad, return to their defaults."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        (void)action;
        [weakSelf resetLayout];
    }]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)resetLayout {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:SunPadExperimentalDPadOriginKey];
    [defaults removeObjectForKey:SunPadExperimentalDPadScaleKey];
    [defaults removeObjectForKey:@"SunPadControlOrigins"];
    [defaults removeObjectForKey:@"SunPadControlSizeScales"];
    [defaults removeObjectForKey:@"SunPadControlSizeScale"];
    [defaults removeObjectForKey:@"SunPadControlOpacity"];
    [[SunPadSettings sharedSettings] resetControlSizeScales];
    [[SunPadSettings sharedSettings] synchronize];
    [self applySettings];
    [self setNeedsLayout];
}

#pragma mark - Layout editing (drag + persist)

- (void)addEditGesturesToControl:(UIView *)control {
    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(controlDragged:)];
    drag.enabled = NO;
    drag.cancelsTouchesInView = YES;
    drag.delegate = self;
    [control addGestureRecognizer:drag];
    [_editGestures addObject:drag];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(controlSelected:)];
    tap.enabled = NO;
    tap.cancelsTouchesInView = YES;
    [control addGestureRecognizer:tap];
    [_editGestures addObject:tap];
}

- (NSArray<UIView *> *)gameplayControls {
    NSMutableArray<UIView *> *controls = [NSMutableArray arrayWithArray:_buttons];
    if (_moveStick != nil) [controls addObject:_moveStick];
    if (_cStick != nil) [controls addObject:_cStick];
    return controls;
}

- (BOOL)isDPadButton:(UIView *)control {
    if (![control isKindOfClass:SunPadGameButton.class])
        return NO;
    uint16_t mask = ((SunPadGameButton *)control).inputMask;
    return mask == SunPadButtonDpadUp || mask == SunPadButtonDpadDown ||
           mask == SunPadButtonDpadLeft || mask == SunPadButtonDpadRight;
}

- (BOOL)isEditableControl:(UIView *)control {
    if (control == _experimentalDPadGroup)
        return YES;
    if ([self isDPadButton:control])
        return NO;
    return YES;
}

- (void)updateControlAppearance {
    BOOL hidden = _touchControlsHidden && !_editingLayout;
    CGFloat alpha = _editingLayout ? 1.0 : [SunPadSettings sharedSettings].controlOpacity;
    BOOL groupedDPad = YES;
    for (UIView *control in [self gameplayControls]) {
        control.hidden = hidden;
        control.userInteractionEnabled = !hidden;
        control.alpha = hidden ? 0.0 : alpha;
        UIColor *border = [UIColor colorWithWhite:1.0 alpha:0.68];
        CGFloat borderWidth = 2.0;
        if (_editingLayout && !(groupedDPad && [self isDPadButton:control])) {
            border = control == _selectedControl
                ? [UIColor colorWithRed:0.20 green:0.78 blue:1.0 alpha:1.0]
                : [UIColor colorWithRed:1.0 green:0.78 blue:0.20 alpha:0.95];
            borderWidth = control == _selectedControl ? 4.0 : 3.0;
        }
        control.layer.borderColor = border.CGColor;
        control.layer.borderWidth = borderWidth;
    }

    BOOL showDPadGroup = _editingLayout && !hidden;
    _experimentalDPadGroup.hidden = !showDPadGroup;
    _experimentalDPadGroup.userInteractionEnabled = showDPadGroup;
    _experimentalDPadGroup.alpha = showDPadGroup ? 1.0 : 0.0;
    _experimentalDPadGroup.layer.borderColor =
        (_selectedControl == _experimentalDPadGroup ?
            [UIColor colorWithRed:0.20 green:0.78 blue:1.0 alpha:1.0] :
            [UIColor colorWithRed:1.0 green:0.78 blue:0.20 alpha:0.95]).CGColor;
    _experimentalDPadGroup.layer.borderWidth =
        _selectedControl == _experimentalDPadGroup ? 4.0 : 3.0;
    if (showDPadGroup)
        [self bringSubviewToFront:_experimentalDPadGroup];
}

- (void)beginLayoutEditing {
    _editingLayout = YES;
    _settingsPanel.hidden = YES;
    _editorBar.hidden = NO;
    _selectedControl = nil;
    _selectedSizeSlider.enabled = NO;
    _selectedSizeSlider.value = 1.0;
    _editorHintLabel.text = @"Drag controls • tap one to resize";
    [self clearTouchInput];
    for (UIGestureRecognizer *gesture in _editGestures)
        gesture.enabled = [self isEditableControl:gesture.view];
    [self updateControlAppearance];
    [self setNeedsLayout];
}

- (void)endLayoutEditing {
    [self clearTouchInput];
    _editingLayout = NO;
    _editorBar.hidden = YES;
    for (UIGestureRecognizer *gesture in _editGestures)
        gesture.enabled = NO;
    _selectedControl = nil;
    _selectedSizeSlider.enabled = NO;
    _selectedSizeSlider.value = 1.0;
    _editorHintLabel.text = @"Drag controls • tap one to resize";
    [self applyControllerVisibility];
    [self updateControlAppearance];
}

- (NSString *)identifierForMask:(uint16_t)mask {
    switch (mask) {
    case SunPadButtonA: return @"A";
    case SunPadButtonB: return @"B";
    case SunPadButtonX: return @"X";
    case SunPadButtonY: return @"Y";
    case SunPadButtonZ: return @"Z";
    case SunPadButtonStart: return @"Start";
    case SunPadButtonL: return @"L";
    case SunPadButtonR: return @"R";
    case SunPadButtonDpadUp: return @"D_U";
    case SunPadButtonDpadDown: return @"D_D";
    case SunPadButtonDpadLeft: return @"D_L";
    case SunPadButtonDpadRight: return @"D_R";
    default: return @"";
    }
}

- (void)controlDragged:(UIPanGestureRecognizer *)drag {
    if (!_editingLayout || drag.view == nil)
        return;
    UIView *control = drag.view;
    if (drag.state == UIGestureRecognizerStateBegan)
        [self selectControlForEditing:control];
    CGPoint translation = [drag translationInView:self];
    CGPoint center = CGPointMake(control.center.x + translation.x,
                                 control.center.y + translation.y);
    [drag setTranslation:CGPointZero inView:self];

    CGRect safe = self.bounds;
    if (@available(iOS 11.0, *))
        safe = UIEdgeInsetsInsetRect(safe, self.safeAreaInsets);
    CGFloat halfWidth = MIN(control.bounds.size.width * 0.5, safe.size.width * 0.5);
    CGFloat halfHeight = MIN(control.bounds.size.height * 0.5, safe.size.height * 0.5);
    center.x = std::clamp(center.x, CGRectGetMinX(safe) + halfWidth,
                          CGRectGetMaxX(safe) - halfWidth);
    center.y = std::clamp(center.y, CGRectGetMinY(safe) + halfHeight,
                          CGRectGetMaxY(safe) - halfHeight);
    control.center = center;
    if (control == _experimentalDPadGroup)
        [self layoutExperimentalDPadButtons];

    if (drag.state == UIGestureRecognizerStateEnded ||
        drag.state == UIGestureRecognizerStateCancelled) {
        NSString *identifier = control.accessibilityIdentifier;
        if (identifier.length == 0 || safe.size.width <= 0.0 || safe.size.height <= 0.0)
            return;
        CGPoint normalized = CGPointMake(
            (center.x - CGRectGetMinX(safe)) / safe.size.width,
            (center.y - CGRectGetMinY(safe)) / safe.size.height);
        if (control == _experimentalDPadGroup) {
            [[NSUserDefaults standardUserDefaults]
                setObject:NSStringFromCGPoint(normalized)
                   forKey:SunPadExperimentalDPadOriginKey];
        } else {
            NSMutableDictionary *saved = [[[NSUserDefaults standardUserDefaults]
                dictionaryForKey:@"SunPadControlOrigins"] mutableCopy];
            if (saved == nil)
                saved = [NSMutableDictionary dictionary];
            saved[identifier] = NSStringFromCGPoint(normalized);
            [[NSUserDefaults standardUserDefaults] setObject:saved forKey:@"SunPadControlOrigins"];
        }
        [[SunPadSettings sharedSettings] synchronize];
    }
}

- (void)controlSelected:(UITapGestureRecognizer *)tap {
    if (tap.state == UIGestureRecognizerStateEnded)
        [self selectControlForEditing:tap.view];
}

- (void)selectControlForEditing:(UIView *)control {
    if (!_editingLayout || control.accessibilityIdentifier.length == 0)
        return;
    _selectedControl = control;
    _selectedSizeSlider.value = control == _experimentalDPadGroup ?
        [self experimentalDPadScale] :
        [[SunPadSettings sharedSettings] sizeScaleForControl:control.accessibilityIdentifier];
    _selectedSizeSlider.enabled = YES;
    _selectedSizeSlider.accessibilityLabel = [NSString stringWithFormat:@"%@ size",
                                               control.accessibilityLabel];
    _editorHintLabel.text = [NSString stringWithFormat:@"%@ size", control.accessibilityLabel];
    [self updateControlAppearance];
}

- (void)selectedSizeChanged:(UISlider *)slider {
    NSString *identifier = _selectedControl.accessibilityIdentifier;
    if (!_editingLayout || identifier.length == 0)
        return;
    if (_selectedControl == _experimentalDPadGroup) {
        [[NSUserDefaults standardUserDefaults]
            setDouble:std::clamp<double>(slider.value, 0.60, 1.75)
               forKey:SunPadExperimentalDPadScaleKey];
    } else {
        [[SunPadSettings sharedSettings] setSizeScale:slider.value forControl:identifier];
    }
    [[SunPadSettings sharedSettings] synchronize];
    [self setNeedsLayout];
}

#pragma mark - Settings application

- (void)applySettings {
    SunPadSettings *settings = [SunPadSettings sharedSettings];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SunPadEditingControlLayout"];
    _renderScaleControl.selectedSegmentIndex = settings.renderScale - 1;
    _opacitySlider.value = settings.controlOpacity;
    _sizeSlider.value = settings.controlSizeScale;
    _hideControlsSwitch.on = settings.hideTouchControlsWhenControllerConnected;
    _modernCStickSwitch.on = settings.modernCStickHorizontal;
    _invertCStickVerticalSwitch.on = settings.invertCStickVertical;
    _editLayoutSwitch.on = NO;
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:@"SunPadExperimentalTouchControls"];
    [_resetLayoutButton setTitle:@"Reset This Device Layout"
                        forState:UIControlStateNormal];
    [self endLayoutEditing];
    [self setNeedsLayout];
}

- (void)setTouchControlsHidden:(BOOL)hidden animated:(BOOL)animated {
    _touchControlsHidden = hidden;
    [UIView animateWithDuration:animated ? 0.25 : 0.0 animations:^{
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }];
}

- (void)applyControllerVisibility {
    BOOL controllerConnected = NO;
#if !TARGET_OS_SIMULATOR
    // Only real hardware controllers hide the touch controls; the Simulator
    // can report virtual controllers that would hide them during testing.
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil) {
            controllerConnected = YES;
            break;
        }
    }
#endif
    BOOL shouldHide = !_editingLayout && controllerConnected &&
        [SunPadSettings sharedSettings].hideTouchControlsWhenControllerConnected;
    [self setTouchControlsHidden:shouldHide animated:YES];
    if (controllerConnected)
        [self clearTouchInput];
}

- (void)refreshControllerVisibility {
    [self applyControllerVisibility];
}

- (void)observeControllerConnection {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyControllerVisibility)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyControllerVisibility)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];
    [self applyControllerVisibility];
}

@end
