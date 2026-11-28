#pragma once

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include "SunPadInputState.h"
#import "SunPadSettings.h"

NS_ASSUME_NONNULL_BEGIN

/* Hosts the decompilation engine (libsms_embed.dylib) inside the SunPad
 * iOS/iPadOS app, implemented in SunPadEngineHost.mm. Owns the engine's
 * thread, the CAMetalLayer it draws to through MoltenVK, its audio and its
 * controller input. gameRoot and modulePath keep their 0.3.x names: modulePath
 * is the engine library and the disc image is read directly. */
@interface SunPadCoreHost : NSObject

- (instancetype)initWithLayer:(CAMetalLayer *)layer NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/* Boots the game on a background thread. Returns immediately; the game runs
 * until -stop is called. Reports errors through onError. */
- (void)startWithGameRoot:(NSString *)gameRoot
            discImagePath:(NSString *)discImagePath
              modulePath:(NSString *)modulePath
              userDirectory:(NSString *)userDirectory
                  onError:(void (^)(NSString *message))onError;

- (void)stop;

/* Pauses/resumes emulation around iOS lifecycle and audio interruptions.
 * Resume also reactivates the app's AVAudioSession. */
- (void)pauseRuntimeForSystemEvent;
- (void)resumeRuntimeAfterSystemEvent;

/* Stops the current runtime (if any) and boots the game at gameRoot with the
 * given module. Used after an imported image is extracted. */
- (void)restartWithGameRoot:(NSString *)gameRoot
               discImagePath:(NSString *)discImagePath
                 modulePath:(NSString *)modulePath;

/* Publishes the normalized input snapshot to the game through the pipe
 * device. Safe to call from any thread at ~60 Hz. */
- (void)publishInput:(SunPadInputState)input;

/* Applies the render-resolution scale (1 = native GameCube EFB, 2..4 = scale)
 * to the running runtime. Safe to call from any thread. */
- (void)setRenderScale:(NSInteger)scale;

/* Records that a changed output aspect ratio will apply on the next launch.
 * The boot-time GMSE01 widescreen code cannot be safely removed live. */
- (void)setAspectRatioMode:(SunPadAspectRatioMode)mode;

/* Current emulated FPS from the runtime (0 if not booted). */
- (double)currentFPS;

/* Emulation speed ratio relative to real time (1.0 = full speed). */
- (double)currentSpeed;

/* Video-interface updates per second, useful when FPS alone looks healthy. */
- (double)currentVPS;

/* The profile actually selected for this runtime, independent of a setting
 * changed after launch. */
- (NSString *)currentPerformanceProfile;

/* Render scale actually applied to this runtime, independent of a stored
 * setting or a controlled launch override. */
- (NSInteger)currentRenderScale;

/* Internal (EFB) render resolution, e.g. "640x528". */
- (NSString *)efbResolution;

/* Bounded, privacy-safe runtime and graphics state for a user-generated
 * diagnostic report. */
- (NSString *)diagnosticSummary;

@property(nonatomic, readonly, getter=isRunning) BOOL running;

@end

NS_ASSUME_NONNULL_END
