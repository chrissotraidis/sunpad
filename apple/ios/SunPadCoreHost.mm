#import "SunPadCoreHost.h"
#import "SunPadDiagnostics.h"
#import "SunPadInputPipeEncoder.h"

#import <AVFAudio/AVFAudio.h>
#import <Metal/Metal.h>
#import <TargetConditionals.h>
#import <fcntl.h>
#import <pthread.h>
#import <sys/stat.h>

#include <atomic>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <string>
#include <thread>

namespace fs = std::filesystem;

/* The ModernGekko runtime header is a C++ header; include it here only. */
#include "moderngekko/runtime.hpp"

#include "Core/Core.h"
#include "Core/Config/StaticRecompSettings.h"
#include "Core/Config/GraphicsSettings.h"
#include "Core/System.h"
#include "VideoCommon/PerformanceMetrics.h"
#include "VideoCommon/VideoConfig.h"

static void SunPadRuntimeLogCallback(
    moderngekko::RuntimeLogLevel level, const char *category,
    const char *message, void *userData) {
    (void)userData;
    @autoreleasepool {
        SunPadLogRuntimeEvent(
            level == moderngekko::RuntimeLogLevel::Error ? @"error" : @"warning",
            category != nullptr ? @(category) : @"runtime",
            message != nullptr ? @(message) : @"unknown runtime event");
    }
}

@interface SunPadCoreHost ()
- (void)applyAspectRatioMode:(SunPadAspectRatioMode)mode source:(NSString *)source;
- (void)applySystemPauseState;
- (void)scheduleSystemStateRetry;
- (void)handleAudioSessionInterruption:(NSNotification *)notification;
@end

@implementation SunPadCoreHost {
    CAMetalLayer *_layer;
    std::thread *_gameThread;
    std::atomic<bool> *_stopRequested;
    std::atomic<bool> *_starting;
    std::atomic<bool> *_running;
    std::mutex *_runtimeMutex;
    moderngekko::Runtime *_runtime;
    int _pipeFd;
    void (^_onError)(NSString *);
    BOOL _applicationActive;
    BOOL _audioInterrupted;
    BOOL _runtimePausedForSystemEvent;
    BOOL _audioSessionDeactivatedForSystemEvent;
    BOOL _audioSessionNeedsReactivation;
    BOOL _systemStateRetryScheduled;
    NSUInteger _systemStateRetryAttempts;
    NSString *_activePerformanceProfile;
    NSString *_activePerformanceSource;
    NSString *_activeFrameMode;
    NSInteger _activeRenderScale;
    unsigned long long _moduleFileSize;
}

- (instancetype)initWithLayer:(CAMetalLayer *)layer {
    if ((self = [super init])) {
        _layer = layer;
        _pipeFd = -1;
        _gameThread = new std::thread();
        _stopRequested = new std::atomic<bool>(false);
        _starting = new std::atomic<bool>(false);
        _running = new std::atomic<bool>(false);
        _runtimeMutex = new std::mutex();
        _runtime = nullptr;
        _applicationActive = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        _audioInterrupted = NO;
        _runtimePausedForSystemEvent = NO;
        _audioSessionDeactivatedForSystemEvent = NO;
        _audioSessionNeedsReactivation = NO;
        _systemStateRetryScheduled = NO;
        _systemStateRetryAttempts = 0;
        _activePerformanceProfile = @"not started";
        _activePerformanceSource = @"none";
        _activeFrameMode = @"not started";
        _activeRenderScale = 1;
        _moduleFileSize = 0;
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(handleAudioSessionInterruption:)
                   name:AVAudioSessionInterruptionNotification
                 object:AVAudioSession.sharedInstance];
    }
    return self;
}

- (BOOL)isRunning {
    return _running->load();
}

- (void)startWithGameRoot:(NSString *)gameRoot
            discImagePath:(NSString *)discImagePath
               modulePath:(NSString *)modulePath
             userDirectory:(NSString *)userDirectory
                   onError:(void (^)(NSString *))onError {
    if (_running->load() || _starting->load() || _gameThread->joinable())
        return;
    _onError = [onError copy];
    *_stopRequested = false;
    *_starting = true;

    NSError *audioSessionError = nil;
    AVAudioSession *audioSession = AVAudioSession.sharedInstance;
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&audioSessionError];
    if (!audioSessionError)
        [audioSession setActive:YES error:&audioSessionError];
    if (audioSessionError)
        SunPadLog(@"audio session setup failed: %@", audioSessionError);
    else
        SunPadLog(@"audio session active route=%@", audioSession.currentRoute.outputs.firstObject.portType ?: @"none");

#if !TARGET_OS_TV
    NSString *pipeDir = [userDirectory stringByAppendingPathComponent:@"Pipes"];
    NSString *pipePath = [pipeDir stringByAppendingPathComponent:@"sunpad"];
    [[NSFileManager defaultManager] createDirectoryAtPath:pipeDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    // The runtime opens the FIFO read-only; recreate if a stale file exists.
    ::unlink(pipePath.fileSystemRepresentation);
    int fifoResult = ::mkfifo(pipePath.fileSystemRepresentation, 0666);
    SunPadLog(@"input pipe create result=%d errno=%d", fifoResult, fifoResult == 0 ? 0 : errno);

    // This is a dedicated virtual GameCube controller. Dolphin's pipe backend
    // is present in the iOS core, but it has no default bindings, so provide
    // its stable mapping before the runtime initializes controllers.
    NSString *configDirectory = [userDirectory stringByAppendingPathComponent:@"Config"];
    [[NSFileManager defaultManager] createDirectoryAtPath:configDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *padConfig =
        @"[GCPad1]\n"
         "Device = Pipe/0/sunpad\n"
         "Buttons/A = `Button A`\n"
         "Buttons/B = `Button B`\n"
         "Buttons/X = `Button X`\n"
         "Buttons/Y = `Button Y`\n"
         "Buttons/Z = `Button Z`\n"
         "Buttons/Start = `Button START`\n"
         "Main Stick/Up = `Axis MAIN Y -`\n"
         "Main Stick/Down = `Axis MAIN Y +`\n"
         "Main Stick/Left = `Axis MAIN X -`\n"
         "Main Stick/Right = `Axis MAIN X +`\n"
         "Main Stick/Calibration = 100.00\n"
         "C-Stick/Up = `Axis C Y -`\n"
         "C-Stick/Down = `Axis C Y +`\n"
         "C-Stick/Left = `Axis C X -`\n"
         "C-Stick/Right = `Axis C X +`\n"
         "C-Stick/Calibration = 100.00\n"
         "Triggers/L = `Axis L +`\n"
         "Triggers/R = `Axis R +`\n"
         "Triggers/L-Analog = `Axis L +`\n"
         "Triggers/R-Analog = `Axis R +`\n"
         "D-Pad/Up = `Button D_UP`\n"
         "D-Pad/Down = `Button D_DOWN`\n"
         "D-Pad/Left = `Button D_LEFT`\n"
         "D-Pad/Right = `Button D_RIGHT`\n";
    [padConfig writeToFile:[configDirectory stringByAppendingPathComponent:@"GCPadNew.ini"]
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];
#endif

    SunPadLog(@"runtime thread starting discImage=%d moduleExists=%d",
              discImagePath.length > 0,
              [[NSFileManager defaultManager] fileExistsAtPath:modulePath]);
    _moduleFileSize = [[[NSFileManager defaultManager]
        attributesOfItemAtPath:modulePath error:nil][NSFileSize] unsignedLongLongValue];
    *_gameThread = std::thread([self, gameRoot, discImagePath, modulePath, userDirectory] {
        [self runGameWithGameRoot:gameRoot
                    discImagePath:discImagePath
                       modulePath:modulePath
                    userDirectory:userDirectory];
    });
}

- (void)runGameWithGameRoot:(NSString *)gameRoot
              discImagePath:(NSString *)discImagePath
                 modulePath:(NSString *)modulePath
              userDirectory:(NSString *)userDirectory {
    std::string errorMessage;
    @autoreleasepool {
        moderngekko::RuntimeConfig config;
        config.game_root = gameRoot.fileSystemRepresentation;
        if (discImagePath.length > 0)
            config.disc_image = discImagePath.fileSystemRepresentation;
        config.user_directory = userDirectory.fileSystemRepresentation;
        config.graphics.backend = "Metal";
        config.headless = false;
        config.show_fps_in_title = false;
        config.log_callback = SunPadRuntimeLogCallback;
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        BOOL stableBaseline = [arguments containsObject:@"-sunpadStableBaseline"];
        NSNumber *savedAspectValue = [[NSUserDefaults standardUserDefaults]
            objectForKey:@"SunPadAspectRatioMode"];
        SunPadAspectRatioMode savedAspect = savedAspectValue ?
            (SunPadAspectRatioMode)savedAspectValue.integerValue : SunPadAspectRatioOriginal;
        if (savedAspect < SunPadAspectRatioOriginal ||
            savedAspect > SunPadAspectRatioFillScreen) {
            savedAspect = SunPadAspectRatioOriginal;
        }
        if (stableBaseline)
            savedAspect = SunPadAspectRatioOriginal;
        config.enable_gmse01_widescreen = savedAspect != SunPadAspectRatioOriginal;
        BOOL launchArgument60FPS =
            [arguments containsObject:@"-sunpadExperimental60FPS"];
        BOOL menuPreference60FPS = [SunPadSettings sharedSettings].experimental60FPS;
        config.enable_gmse01_60fps =
            !stableBaseline && (launchArgument60FPS || menuPreference60FPS);
        BOOL launchArgumentPerformance90 = [arguments
            containsObject:@"-sunpadExperimentalPerformanceMode"];
        BOOL launchArgumentPerformance95 = [arguments
            containsObject:@"-sunpadExperimentalPerformance95"];
        BOOL launchArgumentPerformanceQoSOnly = [arguments
            containsObject:@"-sunpadExperimentalPerformanceQoSOnly"];
        BOOL menuPreferencePerformance =
            [SunPadSettings sharedSettings].experimentalPerformanceMode;

        NSString *performanceProfile = @"stable";
        NSString *performanceSource = stableBaseline ?
            @"stable baseline launch argument" : @"default";
        float emulatedCPUClock = 1.00f;
        BOOL useExperimentalQoS = NO;
        if (!stableBaseline && launchArgumentPerformanceQoSOnly) {
            performanceProfile = @"experimental-qos-only-100";
            performanceSource = @"launch argument";
            useExperimentalQoS = YES;
        } else if (!stableBaseline && launchArgumentPerformance95) {
            performanceProfile = @"experimental-single-core-95";
            performanceSource = @"launch argument";
            emulatedCPUClock = 0.95f;
            useExperimentalQoS = YES;
        } else if (!stableBaseline &&
                   (launchArgumentPerformance90 || menuPreferencePerformance)) {
            performanceProfile = @"experimental-single-core-90";
            performanceSource = launchArgumentPerformance90 ?
                @"launch argument" : @"menu preference";
            emulatedCPUClock = 0.90f;
            useExperimentalQoS = YES;
        }

        if (emulatedCPUClock < 1.00f)
            config.emulated_cpu_clock_scale = emulatedCPUClock;
        int qosResult = 0;
        if (useExperimentalQoS)
            qosResult = pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);
        if (useExperimentalQoS) {
            SunPadLog(@"runtime performance profile=%@ cpuVideoSplit=0 emulatedCPUClock=%.2f gameThreadQoS=userInitiated qosResult=%d source=%@",
                      performanceProfile, emulatedCPUClock, qosResult, performanceSource);
        } else {
            SunPadLog(@"runtime performance profile=stable cpuVideoSplit=0 emulatedCPUClock=1.00 gameThreadQoS=inherited source=%@",
                      performanceSource);
        }
        @synchronized (self) {
            _activePerformanceProfile = performanceProfile;
            _activePerformanceSource = performanceSource;
        }
        config.render_surface = (__bridge void *)_layer;
        config.module = moderngekko::ModuleSource::DynamicPath(
            modulePath.fileSystemRepresentation);

        NSString *frameModeSource = stableBaseline ? @"stable baseline launch argument" :
            (launchArgument60FPS ? @"launch argument" :
             (menuPreference60FPS ? @"menu preference" : @"default"));
        @synchronized (self) {
            _activeFrameMode = config.enable_gmse01_60fps ?
                @"experimental-60-fps" : @"original-30-fps";
        }
        SunPadLog(@"runtime frame mode=%@ source=%@",
                  config.enable_gmse01_60fps ? @"60 FPS experimental" : @"original 30 FPS",
                  frameModeSource);

        auto created = moderngekko::Runtime::Create(std::move(config));
        if (!created) {
            errorMessage = created.error->message;
            *_starting = false;
            SunPadLog(@"runtime create failed: %s", errorMessage.c_str());
            if (_onError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    _onError(@(errorMessage.c_str()));
                });
            }
            return;
        }
        // GMSE01's OS scheduler waits here while no guest thread is runnable.
        // ModernGekko's existing idle seam advances to the next emulated event
        // instead of burning the host CPU on the polling loop.
        Config::SetBase(Config::MAIN_STATICRECOMP_IDLE_PC, 0x80348814u);
        SunPadLog(@"runtime scheduler idle skip=enabled pc=80348814");
        {
            std::scoped_lock lock(*_runtimeMutex);
            _runtime = created.runtime.get();
        }
        if (_stopRequested->load()) {
            std::scoped_lock lock(*_runtimeMutex);
            _runtime = nullptr;
            *_starting = false;
            return;
        }
        *_starting = false;
        *_running = true;
        SunPadLog(@"runtime created");

        // Apply the persisted render-resolution choice now that the runtime's
        // config layers exist.
        NSNumber *savedScaleValue =
            [[NSUserDefaults standardUserDefaults] objectForKey:@"SunPadRenderScale"];
        NSInteger savedScale = savedScaleValue ? savedScaleValue.integerValue : 1;
        NSInteger clampedSavedScale = stableBaseline ? 1 :
            (savedScale < 1 ? 1 : (savedScale > 4 ? 4 : savedScale));
        Config::SetCurrent(Config::GFX_EFB_SCALE, static_cast<int>(clampedSavedScale));
        Config::SetCurrent(Config::GFX_MAX_EFB_SCALE, 12);
        @synchronized (self) {
            _activeRenderScale = clampedSavedScale;
        }
        SunPadLog(@"runtime render scale=%ld source=%@", (long)clampedSavedScale,
                  stableBaseline ? @"stable baseline launch argument" : @"persisted");

        [self applyAspectRatioMode:savedAspect
                           source:stableBaseline ? @"stable baseline launch argument" :
                                                   @"persisted"];

#if !TARGET_OS_TV
        // Open the input FIFO for writing (blocks until the runtime reads it).
        NSString *pipePath = [[userDirectory stringByAppendingPathComponent:@"Pipes"]
            stringByAppendingPathComponent:@"sunpad"];
        for (int attempt = 0; attempt < 600 && !_stopRequested->load(); ++attempt) {
            _pipeFd = ::open(pipePath.fileSystemRepresentation, O_WRONLY | O_NONBLOCK);
            if (_pipeFd >= 0) {
                SunPadLog(@"input pipe connected attempt=%d", attempt + 1);
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        if (_pipeFd < 0)
            SunPadLog(@"input pipe unavailable after wait errno=%d stopRequested=%d", errno,
                      _stopRequested->load());
#endif

        // Run() marks the ModernGekko runtime active before booting. Re-apply
        // any lifecycle state on the main queue so a resign-active event that
        // arrived during startup cannot be lost.
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_systemStateRetryAttempts = 0;
            [self applySystemPauseState];
        });
        auto result = created.runtime->Run();
        {
            std::scoped_lock lock(*_runtimeMutex);
            _runtime = nullptr;
        }
        SunPadLog(@"runtime exited error=%d stopRequested=%d",
                  (bool)result.error, _stopRequested->load());
        if (result.error && _onError) {
            errorMessage = result.error->message;
            dispatch_async(dispatch_get_main_queue(), ^{
                _onError(@(errorMessage.c_str()));
            });
        }
        if (_pipeFd >= 0) {
            ::close(_pipeFd);
            _pipeFd = -1;
        }
    }
    *_running = false;
    *_starting = false;
}

- (void)publishInput:(SunPadInputState)input {
#if TARGET_OS_TV
    (void)input;
#else
    if (_pipeFd < 0)
        return;
    static uint16_t lastButtons = 0;
    BOOL modernCStick = [SunPadSettings sharedSettings].modernCStickHorizontal;
    std::string commands = SunPadEncodePipeCommands(input, lastButtons, modernCStick);
    if (!commands.empty()) {
        ssize_t written = ::write(_pipeFd, commands.data(), commands.size());
        if (written == static_cast<ssize_t>(commands.size())) {
            // Advance edge tracking only after the whole atomic FIFO message
            // is delivered; an EAGAIN will retry the same button transition.
            lastButtons = input.buttons;
        } else if (written < 0 && errno != EAGAIN) {
            SunPadLog(@"input pipe write failed errno=%d bytes=%lu", errno,
                      (unsigned long)commands.size());
        } else if (written >= 0) {
            SunPadLog(@"input pipe partial write bytes=%ld expected=%lu", (long)written,
                      (unsigned long)commands.size());
        }
    }
#endif
}

- (void)setRenderScale:(NSInteger)scale {
    NSInteger clamped = scale < 1 ? 1 : (scale > 4 ? 4 : scale);
    if (!_running->load())
        return; // Runtime not booted yet; the scale applies at boot.
    // Config::SetCurrent is mutex-protected and the video backend refreshes
    // g_ActiveConfig on the next config callback.
    Config::SetCurrent(Config::GFX_EFB_SCALE, static_cast<int>(clamped));
    @synchronized (self) {
        _activeRenderScale = clamped;
    }
    SunPadLog(@"runtime render scale=%ld source=live", (long)clamped);
}

- (void)applyAspectRatioMode:(SunPadAspectRatioMode)mode source:(NSString *)source {
    NSString *modeName = @"original-4:3";
    BOOL suppressHeatwave = mode != SunPadAspectRatioOriginal;
    if (suppressHeatwave) {
        std::scoped_lock lock(*_runtimeMutex);
        if (_runtime)
            _runtime->SetGMSE01HeatwaveSuppressed(true);
    }
    switch (mode) {
    case SunPadAspectRatioWidescreen:
        modeName = @"widescreen-16:9";
        Config::SetCurrent(Config::GFX_ASPECT_RATIO, AspectMode::ForceWide);
        Config::SetCurrent(Config::GFX_WIDESCREEN_HACK, false);
        break;
    case SunPadAspectRatioFillScreen: {
        modeName = @"fill-screen";
        CGSize size = _layer.drawableSize;
        int width = MAX(1, (int)std::lround(size.width));
        int height = MAX(1, (int)std::lround(size.height));
        Config::SetCurrent(Config::GFX_CUSTOM_ASPECT_RATIO_WIDTH, width);
        Config::SetCurrent(Config::GFX_CUSTOM_ASPECT_RATIO_HEIGHT, height);
        Config::SetCurrent(Config::GFX_ASPECT_RATIO, AspectMode::CustomStretch);
        Config::SetCurrent(Config::GFX_WIDESCREEN_HACK, false);
        break;
    }
    case SunPadAspectRatioOriginal:
    default:
        Config::SetCurrent(Config::GFX_ASPECT_RATIO, AspectMode::ForceStandard);
        Config::SetCurrent(Config::GFX_WIDESCREEN_HACK, false);
        break;
    }
    if (!suppressHeatwave) {
        std::scoped_lock lock(*_runtimeMutex);
        if (_runtime)
            _runtime->SetGMSE01HeatwaveSuppressed(false);
    }
    SunPadLog(@"runtime aspect mode=%@ gmse01WidescreenCode=%d genericWidescreenHack=0 "
               "heatwaveSuppressed=%d source=%@",
              modeName, suppressHeatwave, suppressHeatwave, source);
}

- (void)setAspectRatioMode:(SunPadAspectRatioMode)mode {
    if (!_running->load())
        return; // Runtime not booted yet; the mode applies at boot.
    SunPadLog(@"runtime aspect pending=%ld source=menu nextLaunch=1", (long)mode);
}

- (double)currentFPS {
    if (!_running->load())
        return 0.0;
    return Core::System::GetInstance().GetPerfMetrics().GetFPS();
}

- (double)currentSpeed {
    if (!_running->load())
        return 0.0;
    return Core::System::GetInstance().GetPerfMetrics().GetSpeed();
}

- (double)currentVPS {
    if (!_running->load())
        return 0.0;
    return Core::System::GetInstance().GetPerfMetrics().GetVPS();
}

- (NSString *)currentPerformanceProfile {
    @synchronized (self) {
        return _activePerformanceProfile ?: @"unknown";
    }
}

- (NSInteger)currentRenderScale {
    @synchronized (self) {
        return _activeRenderScale;
    }
}

- (NSString *)efbResolution {
    if (!_running->load())
        return @"";
    auto &metrics = Core::System::GetInstance().GetPerfMetrics();
    return [NSString stringWithFormat:@"%ux%u", metrics.GetEFBWidth(),
                                      metrics.GetEFBHeight()];
}

- (NSString *)diagnosticSummary {
    moderngekko::RuntimeDiagnosticsSnapshot diagnostics = {};
    BOOL hasRuntime = NO;
    {
        std::scoped_lock lock(*_runtimeMutex);
        hasRuntime = _runtime != nullptr;
        if (hasRuntime)
            diagnostics = _runtime->GetDiagnosticsSnapshot();
    }
    NSString *profile;
    NSString *profileSource;
    NSString *frameMode;
    NSInteger renderScale;
    @synchronized (self) {
        profile = _activePerformanceProfile;
        profileSource = _activePerformanceSource;
        frameMode = _activeFrameMode;
        renderScale = _activeRenderScale;
    }
    return [NSString stringWithFormat:
        @"runtimeState=%@ paused=%d audioInterrupted=%d\n"
         @"performanceProfile=%@ profileSource=%@ frameMode=%@ activeRenderScale=%ld\n"
         @"metalDevice=%@ moduleBytes=%llu\n"
         @"graphics frames=%llu projectionHash=%016llx draws=%u primitives=%u "
         @"bpLoads=%u cpLoads=%u xfLoads=%u shaderChanges=%u scissors=%u\n"
         @"graphicsResources texturesCreated=%u texturesAlive=%u "
         @"vertexShadersCreated=%u pixelShadersCreated=%u\n",
        hasRuntime ? @"created" : (_starting->load() ? @"starting" :
            (_running->load() ? @"running-without-handle" : @"stopped")),
        _runtimePausedForSystemEvent, _audioInterrupted,
        profile ?: @"unknown", profileSource ?: @"unknown", frameMode ?: @"unknown",
        (long)renderScale,
        _layer.device.name ?: @"unknown", _moduleFileSize,
        diagnostics.frame_count, diagnostics.projection_hash,
        diagnostics.draw_calls, diagnostics.primitives,
        diagnostics.bp_loads, diagnostics.cp_loads, diagnostics.xf_loads,
        diagnostics.shader_changes, diagnostics.scissor_count,
        diagnostics.textures_created, diagnostics.textures_alive,
        diagnostics.vertex_shaders_created, diagnostics.pixel_shaders_created];
}

- (void)stop {
    SunPadLog(@"runtime stop requested starting=%d running=%d",
              _starting->load(), _running->load());
    *_stopRequested = true;
    {
        std::scoped_lock lock(*_runtimeMutex);
        if (_runtime != nullptr)
            _runtime->RequestStop();
    }
    if (_gameThread->joinable())
        _gameThread->join();
    *_starting = false;
    *_running = false;
    _runtimePausedForSystemEvent = NO;
}

- (void)pauseRuntimeForSystemEvent {
    _applicationActive = NO;
    _systemStateRetryAttempts = 0;
    [self applySystemPauseState];
}

- (void)resumeRuntimeAfterSystemEvent {
    _applicationActive = YES;
    if (_audioInterrupted) {
        // iOS can omit the interruption-ended notification after system UI
        // such as screenshot capture. Foreground activation is our recovery
        // boundary; setActive below remains the authority and will retry if a
        // real interruption still owns the audio session.
        _audioInterrupted = NO;
        SunPadLog(@"audio interruption latch cleared on foreground activation");
    }
    _systemStateRetryAttempts = 0;
    [self applySystemPauseState];
}

- (void)applySystemPauseState {
    BOOL shouldPause = !_applicationActive || _audioInterrupted;
    if (shouldPause) {
        _audioSessionNeedsReactivation = YES;
        if (!_audioSessionDeactivatedForSystemEvent) {
            NSError *audioError = nil;
            [AVAudioSession.sharedInstance
                setActive:NO
               withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                     error:&audioError];
            if (audioError) {
                SunPadLog(@"audio session deactivation failed: %@", audioError);
            } else {
                _audioSessionDeactivatedForSystemEvent = YES;
            }
        }

        if (_runtimePausedForSystemEvent)
            return;

        std::optional<moderngekko::RuntimeError> pauseError;
        BOOL hadRuntime = NO;
        BOOL corePaused = NO;
        {
            std::scoped_lock lock(*_runtimeMutex);
            hadRuntime = _runtime != nullptr;
            if (hadRuntime) {
                pauseError = _runtime->Pause();
                corePaused = !pauseError &&
                    Core::GetState(Core::System::GetInstance()) == Core::State::Paused;
            }
        }
        if (hadRuntime && corePaused) {
            _runtimePausedForSystemEvent = YES;
            _systemStateRetryAttempts = 0;
            SunPadLog(@"runtime paused for system event");
        } else {
            if (_systemStateRetryAttempts == 0 && pauseError)
                SunPadLog(@"runtime pause pending: %s", pauseError->message.c_str());
            else if (_systemStateRetryAttempts == 0 && hadRuntime)
                SunPadLog(@"runtime pause pending: core not yet pausable");
            else if (_systemStateRetryAttempts == 0)
                SunPadLog(@"runtime pause pending: runtime not created");
            if (hadRuntime || _starting->load())
                [self scheduleSystemStateRetry];
        }
        return;
    }

    if (_audioSessionNeedsReactivation) {
        NSError *audioError = nil;
        [AVAudioSession.sharedInstance setActive:YES error:&audioError];
        if (audioError) {
            if (_systemStateRetryAttempts == 0)
                SunPadLog(@"audio session reactivation pending: %@", audioError);
            [self scheduleSystemStateRetry];
            return;
        }
        _audioSessionNeedsReactivation = NO;
        _audioSessionDeactivatedForSystemEvent = NO;
        _systemStateRetryAttempts = 0;
        SunPadLog(@"audio session reactivated route=%@",
                  AVAudioSession.sharedInstance.currentRoute.outputs.firstObject.portType ?: @"none");
    }

    if (!_runtimePausedForSystemEvent)
        return;

    std::optional<moderngekko::RuntimeError> resumeError;
    BOOL hadRuntime = NO;
    {
        std::scoped_lock lock(*_runtimeMutex);
        hadRuntime = _runtime != nullptr;
        if (hadRuntime)
            resumeError = _runtime->Resume();
    }
    if (hadRuntime && !resumeError) {
        _runtimePausedForSystemEvent = NO;
        _systemStateRetryAttempts = 0;
        SunPadLog(@"runtime resumed after system event");
    } else {
        if (_systemStateRetryAttempts == 0 && resumeError)
            SunPadLog(@"runtime resume pending: %s", resumeError->message.c_str());
        if (hadRuntime || _starting->load())
            [self scheduleSystemStateRetry];
    }
}

- (void)scheduleSystemStateRetry {
    static const NSUInteger kMaxSystemStateRetryAttempts = 20;
    if (_systemStateRetryScheduled ||
        _systemStateRetryAttempts >= kMaxSystemStateRetryAttempts)
        return;
    _systemStateRetryScheduled = YES;
    ++_systemStateRetryAttempts;
    __weak SunPadCoreHost *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        SunPadCoreHost *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        strongSelf->_systemStateRetryScheduled = NO;
        [strongSelf applySystemPauseState];
    });
}

- (void)handleAudioSessionInterruption:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    AVAudioSessionInterruptionType type =
        (AVAudioSessionInterruptionType)[info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        SunPadLog(@"audio interruption began");
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_audioInterrupted = YES;
            self->_systemStateRetryAttempts = 0;
            [self applySystemPauseState];
        });
        return;
    }

    AVAudioSessionInterruptionOptions options =
        (AVAudioSessionInterruptionOptions)[info[AVAudioSessionInterruptionOptionKey]
            unsignedIntegerValue];
    BOOL shouldResume = (options & AVAudioSessionInterruptionOptionShouldResume) != 0;
    SunPadLog(@"audio interruption ended shouldResume=%d", shouldResume);
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_audioInterrupted = NO;
        self->_systemStateRetryAttempts = 0;
        [self applySystemPauseState];
    });
}

- (void)restartWithGameRoot:(NSString *)gameRoot
              discImagePath:(NSString *)discImagePath
                 modulePath:(NSString *)modulePath {
    if (_gameThread->joinable()) {
        [self stop];
    }
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *userDirectory = [paths.firstObject stringByAppendingPathComponent:@"SunPad"];
    [[NSFileManager defaultManager] createDirectoryAtPath:userDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    __weak SunPadCoreHost *weakSelf = self;
    [self startWithGameRoot:gameRoot
              discImagePath:discImagePath
                 modulePath:modulePath
              userDirectory:userDirectory
                    onError:^(NSString *message) {
        (void)weakSelf;
        NSLog(@"[SunPad] runtime error after restart: %@", message);
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_gameThread->joinable())
        [self stop];
    if (_pipeFd >= 0)
        ::close(_pipeFd);
    delete _gameThread;
    delete _stopRequested;
    delete _starting;
    delete _running;
    delete _runtimeMutex;
}

@end
