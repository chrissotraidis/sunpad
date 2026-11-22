// SunPadCoreHost on the decompilation engine (docs/DECOMP-ENGINE-PLAN.md, E3.1).
// The SunPad Next target builds this file in place of SunPadCoreHost.mm, so
// the game view controller and overlay keep their wiring. The engine is
// libsms_embed.dylib, which PadMint builds on the player's computer and adds
// to the app; MoltenVK is linked into the app.
#import "SunPadCoreHost.h"
#import "SunPadControllerRumble.h"
#import "SunPadDiagnostics.h"
#import "SunPadEngineBridge.h"

#import <AVFAudio/AVFAudio.h>
#import <AudioToolbox/AudioToolbox.h>

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

#include "embed/sms_embed.h"

extern "C" void *vkGetInstanceProcAddr(void *instance, const char *name);

namespace {

struct EngineCalls {
    int (*start)(const SmsEmbedConfig *);
    void (*setPad)(int, const SmsEmbedPad *);
    void (*resize)(int, int);
    void (*setScale)(float);
    void (*audioPull)(void *, int);
    void (*pause)(int);
    void (*stats)(SmsEmbedStats *);
};
EngineCalls g_engine;
AudioUnit g_audioUnit;
// The engine runs once per process, as the game does on the console.
BOOL g_engineStarted;

OSStatus RenderEngineAudio(void *, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32 frames,
                           AudioBufferList *buffers) {
    g_engine.audioPull(buffers->mBuffers[0].mData, int(frames * 4));
    return noErr;
}

void EngineRumble(unsigned short strength) {
    [[SunPadControllerRumble sharedRumble] setRumbleEnabled:strength > 0];
}

// Loads the engine and checks its interface. Returns a message for the player, or nil.
NSString *LoadEngine(NSString *path) {
    void *library = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        SunPadLog(@"engine load failed: %s", dlerror());
        return @"SunPad could not load its game engine. Make your copy again with PadMint.";
    }
    auto version = (uint32_t (*)(void))dlsym(library, "sms_embed_version");
    const uint32_t found = version ? version() : 0;
    if (found != SMS_EMBED_VERSION) {
        SunPadLog(@"engine interface %u, app %u", found, SMS_EMBED_VERSION);
        return @"This game engine was made for another version of SunPad. Make your copy again with PadMint.";
    }
    g_engine.start = (int (*)(const SmsEmbedConfig *))dlsym(library, "sms_embed_start");
    g_engine.setPad = (void (*)(int, const SmsEmbedPad *))dlsym(library, "sms_embed_set_pad");
    g_engine.resize = (void (*)(int, int))dlsym(library, "sms_embed_resize");
    g_engine.setScale = (void (*)(float))dlsym(library, "sms_embed_set_scale");
    g_engine.audioPull = (void (*)(void *, int))dlsym(library, "sms_embed_audio_pull");
    g_engine.pause = (void (*)(int))dlsym(library, "sms_embed_pause");
    g_engine.stats = (void (*)(SmsEmbedStats *))dlsym(library, "sms_embed_stats");
    return nil;
}

// RemoteIO plays the engine's 32 kHz stereo; the system converts the rate.
BOOL StartAudioUnit() {
    if (!g_audioUnit) {
        AudioComponentDescription description = {kAudioUnitType_Output, kAudioUnitSubType_RemoteIO,
                                                 kAudioUnitManufacturer_Apple, 0, 0};
        AudioComponent component = AudioComponentFindNext(NULL, &description);
        if (!component || AudioComponentInstanceNew(component, &g_audioUnit) != noErr)
            return NO;
        AudioStreamBasicDescription format = {};
        format.mSampleRate = 32000;
        format.mFormatID = kAudioFormatLinearPCM;
        format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        format.mChannelsPerFrame = 2;
        format.mBitsPerChannel = 16;
        format.mBytesPerFrame = 4;
        format.mFramesPerPacket = 1;
        format.mBytesPerPacket = 4;
        AudioUnitSetProperty(g_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format,
                             sizeof format);
        AURenderCallbackStruct callback = {RenderEngineAudio, NULL};
        AudioUnitSetProperty(g_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback,
                             sizeof callback);
        if (AudioUnitInitialize(g_audioUnit) != noErr)
            return NO;
    }
    return AudioOutputUnitStart(g_audioUnit) == noErr;
}

}  // namespace

@interface SunPadCoreHost ()
- (void)applySystemPauseState;
- (void)handleAudioSessionInterruption:(NSNotification *)notification;
- (void)sampleEngine:(NSTimer *)timer;
@end

@implementation SunPadCoreHost {
    CAMetalLayer *_layer;
    BOOL _running;
    BOOL _applicationActive;
    BOOL _audioInterrupted;
    BOOL _paused;
    void (^_onError)(NSString *);
    NSTimer *_sampleTimer;
    CGSize _drawableSize;
    uint32_t _lastFrames;
    CFTimeInterval _lastSampleTime;
    double _fps;
    NSInteger _renderScale;
    SunPadEngineChoices _choices;
    NSString *_discName;
}

- (instancetype)initWithLayer:(CAMetalLayer *)layer {
    if ((self = [super init])) {
        _layer = layer;
        _applicationActive = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        _renderScale = 1;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleAudioSessionInterruption:)
                                                     name:AVAudioSessionInterruptionNotification
                                                   object:AVAudioSession.sharedInstance];
    }
    return self;
}

- (BOOL)isRunning {
    return _running;
}

- (void)startWithGameRoot:(NSString *)gameRoot
            discImagePath:(NSString *)discImagePath
               modulePath:(NSString *)modulePath
            userDirectory:(NSString *)userDirectory
                  onError:(void (^)(NSString *))onError {
    (void)gameRoot;
    if (_running)
        return;
    _onError = [onError copy];
    if (g_engineStarted) {
        SunPadLog(@"engine already ran in this process: waiting for the next launch");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_onError)
                self->_onError(@"Close SunPad and open it again to play with the new game data.");
        });
        return;
    }
    NSString *failure = LoadEngine(modulePath);
    if (failure) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_onError)
                self->_onError(failure);
        });
        return;
    }

    NSError *audioSessionError = nil;
    AVAudioSession *audioSession = AVAudioSession.sharedInstance;
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&audioSessionError];
    if (!audioSessionError)
        [audioSession setActive:YES error:&audioSessionError];
    if (audioSessionError)
        SunPadLog(@"audio session setup failed: %@", audioSessionError);

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *engineDirectory = [userDirectory stringByAppendingPathComponent:@"Engine"];
    [fileManager createDirectoryAtPath:[engineDirectory stringByAppendingPathComponent:@"card-a"]
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:nil];
    NSString *cacheDirectory =
        NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;

    SunPadSettings *settings = [SunPadSettings sharedSettings];
    _drawableSize = _layer.drawableSize;
    _renderScale = settings.renderScale;
    _choices = {settings.renderScale, settings.aspectRatioMode, settings.experimental60FPS,
                settings.controllerRumble, _drawableSize};
    // A variable already set (a developer launch, a test route) wins over SunPad's choice.
    [SunPadEngineEnvironment(_choices, engineDirectory, cacheDirectory)
        enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
            setenv(name.UTF8String, value.fileSystemRepresentation, 0);
        }];

    // The engine logs to stderr: keep it beside SunPad's own log for problem reports.
    NSString *engineLog = [[SunPadDiagnosticsLogPath() stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"Engine.log"];
    if (!freopen(engineLog.fileSystemRepresentation, "w", stderr))
        SunPadLog(@"engine log unavailable at %@", engineLog.lastPathComponent);
    setvbuf(stderr, NULL, _IOLBF, 0);

    if (!StartAudioUnit())
        SunPadLog(@"engine audio output failed to start");

    _discName = discImagePath.lastPathComponent;
    SmsEmbedConfig config = {};
    config.version = SMS_EMBED_VERSION;
    config.discImage = discImagePath.fileSystemRepresentation;
    config.metalLayer = (__bridge void *)_layer;
    config.getInstanceProcAddr = (void *)vkGetInstanceProcAddr;
    config.width = int(_drawableSize.width);
    config.height = int(_drawableSize.height);
    config.rumble = EngineRumble;
    SunPadLog(@"engine start disc=%@ drawable=%@ scale=%ld frameRate=%s aspect=%ld",
              _discName, NSStringFromCGSize(_drawableSize), (long)_choices.renderScale,
              getenv("SMS_FRAME_RATE"), (long)_choices.aspectRatio);
    if (g_engine.start(&config) != 0) {
        SunPadLog(@"engine start failed");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_onError)
                self->_onError(@"SunPad could not start the game. Close SunPad and open it again.");
        });
        return;
    }
    g_engineStarted = YES;
    _running = YES;
    SunPadInputState idle = {};
    [self publishInput:idle];
    _lastSampleTime = CACurrentMediaTime();
    __weak SunPadCoreHost *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_sampleTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            [weakSelf sampleEngine:timer];
        }];
        [self applySystemPauseState];
    });
}

// Twice a second: the presented frame rate, and the layer's size for the engine.
- (void)sampleEngine:(NSTimer *)timer {
    (void)timer;
    SmsEmbedStats stats = {};
    g_engine.stats(&stats);
    const CFTimeInterval now = CACurrentMediaTime();
    if (now > _lastSampleTime)
        _fps = (stats.frames - _lastFrames) / (now - _lastSampleTime);
    _lastFrames = stats.frames;
    _lastSampleTime = now;
    const CGSize size = _layer.drawableSize;
    if (!CGSizeEqualToSize(size, _drawableSize) && size.width > 0 && size.height > 0) {
        _drawableSize = size;
        g_engine.resize(int(size.width), int(size.height));
    }
}

- (void)publishInput:(SunPadInputState)input {
    if (!_running)
        return;
    SunPadSettings *settings = [SunPadSettings sharedSettings];
    const SmsEmbedPad pad = SunPadEnginePad(input, settings.modernCStickHorizontal, settings.invertCStickVertical);
    g_engine.setPad(0, &pad);
}

- (void)setRenderScale:(NSInteger)scale {
    _renderScale = scale < 1 ? 1 : (scale > 4 ? 4 : scale);
    if (_running)
        g_engine.setScale(float(_renderScale));
    SunPadLog(@"engine render scale=%ld source=live", (long)_renderScale);
}

- (void)setAspectRatioMode:(SunPadAspectRatioMode)mode {
    SunPadLog(@"engine aspect pending=%ld source=menu nextLaunch=1", (long)mode);
}

- (double)currentFPS {
    return _fps;
}

- (double)currentSpeed {
    const double target = _choices.sixtyFPS ? 60.0 : 30.0;
    return _running ? MIN(_fps / target, 1.0) : 0.0;
}

- (double)currentVPS {
    return _fps;
}

- (NSString *)currentPerformanceProfile {
    return _running ? @"decompilation engine" : @"not started";
}

- (NSInteger)currentRenderScale {
    return _renderScale;
}

- (NSString *)efbResolution {
    return [NSString stringWithFormat:@"%ldx%ld", (long)(640 * _renderScale), (long)(528 * _renderScale)];
}

- (NSString *)diagnosticSummary {
    SmsEmbedStats stats = {};
    if (_running)
        g_engine.stats(&stats);
    return [NSString stringWithFormat:
                         @"engine=decompilation interface=%u running=%d frames=%u fps=%.1f lastPresentMs=%.2f "
                          "scale=%ld frameRate=%d aspect=%ld drawable=%@ paused=%d",
                         SMS_EMBED_VERSION, _running, stats.frames, _fps, stats.lastPresentSeconds * 1000.0,
                         (long)_renderScale, _choices.sixtyFPS ? 60 : 30, (long)_choices.aspectRatio,
                         NSStringFromCGSize(_drawableSize), _paused];
}

// The game runs until SunPad closes, as on the console: new game data takes
// effect when SunPad next opens.
- (void)stop {
    SunPadLog(@"engine stop requested running=%d: the engine stops with the app", _running);
}

- (void)restartWithGameRoot:(NSString *)gameRoot
              discImagePath:(NSString *)discImagePath
                 modulePath:(NSString *)modulePath {
    (void)gameRoot;
    (void)discImagePath;
    (void)modulePath;
    SunPadLog(@"engine restart requested: waiting for the next launch");
    if (_onError)
        _onError(@"Close SunPad and open it again to play with the new game data.");
}

- (void)pauseRuntimeForSystemEvent {
    _applicationActive = NO;
    [self applySystemPauseState];
}

- (void)resumeRuntimeAfterSystemEvent {
    _applicationActive = YES;
    // iOS can omit the interruption's end after system UI such as a screenshot;
    // coming back to the foreground is the recovery point.
    _audioInterrupted = NO;
    [self applySystemPauseState];
}

// In the background or during an audio interruption the game waits at its
// next frame with the GPU idle and the audio unit stopped.
- (void)applySystemPauseState {
    if (!_running)
        return;
    const BOOL shouldPause = !_applicationActive || _audioInterrupted;
    if (shouldPause == _paused)
        return;
    if (shouldPause) {
        AudioOutputUnitStop(g_audioUnit);
        g_engine.pause(1);
        [AVAudioSession.sharedInstance setActive:NO
                                     withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                           error:nil];
        _paused = YES;
        SunPadLog(@"engine paused for system event");
        return;
    }
    NSError *audioError = nil;
    [AVAudioSession.sharedInstance setActive:YES error:&audioError];
    if (audioError)
        SunPadLog(@"audio session reactivation failed: %@", audioError);
    StartAudioUnit();
    g_engine.pause(0);
    _paused = NO;
    SunPadLog(@"engine resumed after system event");
}

- (void)handleAudioSessionInterruption:(NSNotification *)notification {
    const AVAudioSessionInterruptionType type = (AVAudioSessionInterruptionType)[
        notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    SunPadLog(@"audio interruption %@", type == AVAudioSessionInterruptionTypeBegan ? @"began" : @"ended");
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_audioInterrupted = type == AVAudioSessionInterruptionTypeBegan;
        [self applySystemPauseState];
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_sampleTimer invalidate];
}

@end
