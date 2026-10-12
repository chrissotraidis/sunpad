#import "SunPadSettings.h"

@implementation SunPadSettings {
    NSMutableDictionary<NSString *, NSNumber *> *_controlSizeScales;
}

+ (instancetype)sharedSettings {
    static SunPadSettings *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[SunPadSettings alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSDictionary *saved = [[NSUserDefaults standardUserDefaults]
            dictionaryForKey:@"SunPadControlSizeScales"];
        _controlSizeScales = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSInteger)renderScale {
    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:@"SunPadRenderScale"];
    if (value == nil)
        return 1;
    NSInteger scale = value.integerValue;
    return scale < 1 ? 1 : (scale > 4 ? 4 : scale);
}

- (void)setRenderScale:(NSInteger)renderScale {
    NSInteger clamped = renderScale < 1 ? 1 : (renderScale > 4 ? 4 : renderScale);
    [[NSUserDefaults standardUserDefaults] setInteger:clamped forKey:@"SunPadRenderScale"];
}

- (float)renderScaleFloat {
    switch (self.renderScale) {
    case 1: return 1.0f;
    case 2: return 2.0f;
    case 3: return 3.0f;
    case 4: return 4.0f;
    default: return 1.0f;
    }
}

- (SunPadAspectRatioMode)aspectRatioMode {
    NSInteger mode = [[NSUserDefaults standardUserDefaults]
        integerForKey:@"SunPadAspectRatioMode"];
    if (mode < SunPadAspectRatioOriginal || mode > SunPadAspectRatioFillScreen)
        return SunPadAspectRatioOriginal;
    return (SunPadAspectRatioMode)mode;
}

- (void)setAspectRatioMode:(SunPadAspectRatioMode)aspectRatioMode {
    NSInteger mode = aspectRatioMode;
    if (mode < SunPadAspectRatioOriginal || mode > SunPadAspectRatioFillScreen)
        mode = SunPadAspectRatioOriginal;
    [[NSUserDefaults standardUserDefaults] setInteger:mode
                                               forKey:@"SunPadAspectRatioMode"];
}

- (BOOL)showFPSCounter {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"SunPadShowFPSCounter"];
}

- (void)setShowFPSCounter:(BOOL)showFPSCounter {
    [[NSUserDefaults standardUserDefaults] setBool:showFPSCounter
                                            forKey:@"SunPadShowFPSCounter"];
}

- (BOOL)experimental60FPS {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"SunPadExperimental60FPS"];
}

- (void)setExperimental60FPS:(BOOL)experimental60FPS {
    [[NSUserDefaults standardUserDefaults] setBool:experimental60FPS
                                            forKey:@"SunPadExperimental60FPS"];
}

- (BOOL)experimentalPerformanceMode {
    return [[NSUserDefaults standardUserDefaults]
        boolForKey:@"SunPadExperimentalPerformanceMode"];
}

- (void)setExperimentalPerformanceMode:(BOOL)experimentalPerformanceMode {
    [[NSUserDefaults standardUserDefaults] setBool:experimentalPerformanceMode
                                            forKey:@"SunPadExperimentalPerformanceMode"];
}

- (BOOL)hideTouchControlsWhenControllerConnected {
    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:@"SunPadHideControlsOnController"];
    return value == nil ? YES : value.boolValue;
}

- (void)setHideTouchControlsWhenControllerConnected:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:@"SunPadHideControlsOnController"];
}

- (BOOL)modernCStickHorizontal {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"SunPadModernCStickHorizontal"];
}

- (void)setModernCStickHorizontal:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:@"SunPadModernCStickHorizontal"];
}

- (BOOL)invertCStickVertical {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"SunPadInvertCStickVertical"];
}

- (void)setInvertCStickVertical:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:@"SunPadInvertCStickVertical"];
}

- (BOOL)controllerRumble {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"SunPadControllerRumble"];
}

- (void)setControllerRumble:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:@"SunPadControllerRumble"];
}

- (CGFloat)controlOpacity {
    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:@"SunPadControlOpacity"];
    if (value == nil)
        return 0.82;
    return MAX(0.25, MIN(1.0, value.doubleValue));
}

- (void)setControlOpacity:(CGFloat)controlOpacity {
    [[NSUserDefaults standardUserDefaults] setDouble:MAX(0.25, MIN(1.0, controlOpacity))
                                              forKey:@"SunPadControlOpacity"];
}

- (CGFloat)controlSizeScale {
    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:@"SunPadControlSizeScale"];
    if (value == nil)
        return 1.0;
    return MAX(0.70, MIN(1.35, value.doubleValue));
}

- (void)setControlSizeScale:(CGFloat)controlSizeScale {
    [[NSUserDefaults standardUserDefaults] setDouble:MAX(0.70, MIN(1.35, controlSizeScale))
                                              forKey:@"SunPadControlSizeScale"];
}

- (BOOL)editingControlLayout {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"SunPadEditingControlLayout"];
}

- (void)setEditingControlLayout:(BOOL)editingControlLayout {
    [[NSUserDefaults standardUserDefaults] setBool:editingControlLayout forKey:@"SunPadEditingControlLayout"];
}

- (CGFloat)sizeScaleForControl:(NSString *)identifier {
    NSNumber *saved = _controlSizeScales[identifier];
    if (saved == nil)
        return 1.0;
    return MAX(0.60, MIN(1.75, saved.doubleValue));
}

- (void)setSizeScale:(CGFloat)scale forControl:(NSString *)identifier {
    _controlSizeScales[identifier] = @(MAX(0.60, MIN(1.75, scale)));
    [[NSUserDefaults standardUserDefaults] setObject:_controlSizeScales
                                              forKey:@"SunPadControlSizeScales"];
}

- (void)resetControlSizeScales {
    [_controlSizeScales removeAllObjects];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SunPadControlSizeScales"];
}

- (NSString *)retainedGameDataPath {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"SunPadRetainedGameDataPath"];
}

- (void)setRetainedGameDataPath:(NSString *)retainedGameDataPath {
    if (retainedGameDataPath == nil) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SunPadRetainedGameDataPath"];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:retainedGameDataPath
                                                  forKey:@"SunPadRetainedGameDataPath"];
    }
}

- (NSString *)extractedGameRoot {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"SunPadExtractedGameRoot"];
}

- (void)setExtractedGameRoot:(NSString *)extractedGameRoot {
    if (extractedGameRoot == nil) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SunPadExtractedGameRoot"];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:extractedGameRoot
                                                  forKey:@"SunPadExtractedGameRoot"];
    }
}

- (void)synchronize {
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
