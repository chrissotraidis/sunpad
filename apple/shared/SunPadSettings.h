#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SunPadAspectRatioMode) {
    SunPadAspectRatioOriginal = 0,
    SunPadAspectRatioWidescreen = 1,
    SunPadAspectRatioFillScreen = 2,
};

/* Persisted SunPad settings shared by macOS, iOS, and iPadOS. Stored in
 * NSUserDefaults so each platform keeps the same user-facing options.
 */
@interface SunPadSettings : NSObject

+ (instancetype)sharedSettings;

/* Render-resolution scale. 1 = native GameCube EFB, 2..4 = multiplier. */
@property(nonatomic, assign) NSInteger renderScale;
- (float)renderScaleFloat;

/* Output aspect ratio. Original 4:3 is the stable default; wider modes are
 * experimental and affect only game rendering, never touch-control layout. */
@property(nonatomic, assign) SunPadAspectRatioMode aspectRatioMode;

/* Optional developer performance overlay. Off by default for normal play. */
@property(nonatomic, assign) BOOL showFPSCounter;

/* Experimental GMSE01 60 FPS boot mode. Off by default and applied only on
 * the next app launch. */
@property(nonatomic, assign) BOOL experimental60FPS;

/* Experimental weak-device performance policy. Off by default and applied on
 * the next app launch. It retains single-core synchronization while reducing
 * the emulated CPU clock to 90%. */
@property(nonatomic, assign) BOOL experimentalPerformanceMode;

/* Touch-control presentation. */
@property(nonatomic, assign) BOOL hideTouchControlsWhenControllerConnected;
/* Reverses only the C-stick horizontal axis for modern camera movement. */
@property(nonatomic, assign) BOOL modernCStickHorizontal;
/* Reverses only the C-stick vertical axis (camera height and zoom). */
@property(nonatomic, assign) BOOL invertCStickVertical;
/* Plays the game's rumble on player one's controller. Off by default. */
@property(nonatomic, assign) BOOL controllerRumble;
@property(nonatomic, assign) CGFloat controlOpacity;   // 0.25..1
@property(nonatomic, assign) CGFloat controlSizeScale; // 0.70..1.35
@property(nonatomic, assign) BOOL editingControlLayout;

/* Per-control size overrides (1.0 = default), keyed by control identifier. */
- (CGFloat)sizeScaleForControl:(NSString *)identifier;
- (void)setSizeScale:(CGFloat)scale forControl:(NSString *)identifier;
- (void)resetControlSizeScales;

/* Save/load the retained game-data path (Application Support on mobile). */
@property(nonatomic, copy, nullable) NSString *retainedGameDataPath;

/* Extracted game tree (sys/ + files/) produced from the retained image. */
@property(nonatomic, copy, nullable) NSString *extractedGameRoot;

- (void)synchronize;

@end

NS_ASSUME_NONNULL_END
