#pragma once

#import <UIKit/UIKit.h>

#include "SunPadInputState.h"

NS_ASSUME_NONNULL_BEGIN

@class SunPadGameOverlay;

@protocol SunPadGameOverlayDelegate <NSObject>
/* The user asked to change or reimport the game data image. */
- (void)gameOverlayRequestsGameDataChange:(SunPadGameOverlay *)overlay;
/* The user asked to import an image dropped into the Files-visible app folder. */
- (void)gameOverlayRequestsGameDataFolderImport:(SunPadGameOverlay *)overlay;
/* The user confirmed removal of the retained image and extracted game tree. */
- (void)gameOverlayRequestsGameDataRemoval:(SunPadGameOverlay *)overlay;
/* The user asked to import a Dolphin .gci save. */
- (void)gameOverlayRequestsSaveImport:(SunPadGameOverlay *)overlay;
/* Copies the current saves for sharing, or returns nil with a readable error. */
- (nullable NSArray<NSURL *> *)gameOverlayExportSaves:(SunPadGameOverlay *)overlay
                                                error:(NSError **)error;
/* The user asked to configure the narrow physical-controller face-button map. */
- (void)gameOverlayRequestsControllerMapping:(SunPadGameOverlay *)overlay;
/* Current privacy-safe app/runtime state for a user-generated problem report. */
- (NSString *)gameOverlayDiagnosticContext:(SunPadGameOverlay *)overlay;
/* The performance profile actually selected at launch. */
- (NSString *)gameOverlayPerformanceProfile:(SunPadGameOverlay *)overlay;
@end

/* UIKit overlay above the game render surface: the three-dot menu, render
 * resolution choices (Native/1x/2x/3x/4x), touch-control settings, and the
 * Sunshine GameCube touch controls (main stick, C-stick, D-pad,
 * A/B/X/Y/Z/Start/L/R). Touch state is published to the shared input mixer
 * (BellPad's canonical boundary). */
@interface SunPadGameOverlay : UIView

@property(nonatomic, weak, nullable) id<SunPadGameOverlayDelegate> delegate;

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/* Hide the touch controls (e.g., a physical controller is connected). */
- (void)setTouchControlsHidden:(BOOL)hidden animated:(BOOL)animated;

/* Re-evaluates the current GameController enumeration after foreground resume. */
- (void)refreshControllerVisibility;

/* Applies persisted settings to the touch controls. */
- (void)applySettings;

@end

NS_ASSUME_NONNULL_END
