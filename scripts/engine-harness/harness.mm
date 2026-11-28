// A minimal app that runs the decompilation engine the way SunPad will
// (docs/DECOMP-ENGINE-PLAN.md, task E2.3): its own CAMetalLayer, MoltenVK
// linked in, RemoteIO pulling the sound, and libsms_embed.dylib loaded from
// the app. Environment (simctl launch with SIMCTL_CHILD_ prefixes):
//   SUNPAD_DISC     the GMSE01 image to play
//   SUNPAD_SCRIPT   "boot": press Start and A on a timer to get past the title
// Every SMS_* variable is passed to the engine unchanged.
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>

#include "embed/sms_embed.h"

extern "C" void* vkGetInstanceProcAddr(void* instance, const char* name);

namespace {

struct Engine {
    int (*start)(const SmsEmbedConfig*);
    void (*setPad)(int, const SmsEmbedPad*);
    void (*resize)(int, int);
    void (*audioPull)(void*, int);
    void (*pause)(int);
    void (*stats)(SmsEmbedStats*);
} engine;

AudioUnit s_audioUnit;

OSStatus RenderAudio(void*, AudioUnitRenderActionFlags*, const AudioTimeStamp*, UInt32, UInt32 frames,
                     AudioBufferList* buffers) {
    engine.audioPull(buffers->mBuffers[0].mData, int(frames * 4));
    return noErr;
}

void StartAudio() {
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    AudioComponentDescription description = {kAudioUnitType_Output, kAudioUnitSubType_RemoteIO,
                                             kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponentInstanceNew(AudioComponentFindNext(NULL, &description), &s_audioUnit);
    AudioStreamBasicDescription format = {};
    format.mSampleRate = 32000;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 16;
    format.mBytesPerFrame = 4;
    format.mFramesPerPacket = 1;
    format.mBytesPerPacket = 4;
    AudioUnitSetProperty(s_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format);
    AURenderCallbackStruct callback = {RenderAudio, NULL};
    AudioUnitSetProperty(s_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback,
                         sizeof callback);
    AudioUnitInitialize(s_audioUnit);
    AudioOutputUnitStart(s_audioUnit);
}

bool LoadEngine() {
    NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"libsms_embed.dylib"];
    void *library = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        NSLog(@"[harness] dlopen failed: %s", dlerror());
        return false;
    }
    auto version = (uint32_t (*)(void))dlsym(library, "sms_embed_version");
    if (!version || version() != SMS_EMBED_VERSION) {
        NSLog(@"[harness] engine interface %u, harness %u", version ? version() : 0, SMS_EMBED_VERSION);
        return false;
    }
    engine.start = (int (*)(const SmsEmbedConfig*))dlsym(library, "sms_embed_start");
    engine.setPad = (void (*)(int, const SmsEmbedPad*))dlsym(library, "sms_embed_set_pad");
    engine.resize = (void (*)(int, int))dlsym(library, "sms_embed_resize");
    engine.audioPull = (void (*)(void*, int))dlsym(library, "sms_embed_audio_pull");
    engine.pause = (void (*)(int))dlsym(library, "sms_embed_pause");
    engine.stats = (void (*)(SmsEmbedStats*))dlsym(library, "sms_embed_stats");
    return engine.start && engine.setPad && engine.resize && engine.audioPull && engine.pause && engine.stats;
}

// "boot": Start, then A, every 1.5 seconds, past the title and the file select.
void RunScript(NSString *script) {
    if (![script isEqualToString:@"boot"])
        return;
    dispatch_queue_t queue = dispatch_queue_create("harness.script", DISPATCH_QUEUE_SERIAL);
    dispatch_async(queue, ^{
        for (int step = 0;; step++) {
            SmsEmbedPad pad = {};
            pad.connected = 1;
            engine.setPad(0, &pad);
            [NSThread sleepForTimeInterval:1.3];
            pad.buttons = step % 2 ? 0x0100 : 0x1000;  // PAD_BUTTON_A, PAD_BUTTON_START
            engine.setPad(0, &pad);
            [NSThread sleepForTimeInterval:0.2];
            if (step % 10 == 0) {
                SmsEmbedStats stats = {};
                engine.stats(&stats);
                NSLog(@"[harness] frames %u, last present %.2f ms", stats.frames, stats.lastPresentSeconds * 1000);
            }
        }
    });
}

}  // namespace

@interface MetalView : UIView
@end
@implementation MetalView
+ (Class)layerClass {
    return [CAMetalLayer class];
}
@end

@interface GameController : UIViewController
@end
@implementation GameController {
    BOOL _started;
}
- (void)loadView {
    self.view = [MetalView new];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CAMetalLayer *layer = (CAMetalLayer *)self.view.layer;
    const CGFloat scale = self.view.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
    layer.contentsScale = scale;
    const int width = int(self.view.bounds.size.width * scale), height = int(self.view.bounds.size.height * scale);
    layer.drawableSize = CGSizeMake(width, height);
    if (_started) {
        engine.resize(width, height);
        return;
    }
    _started = YES;
    NSDictionary *environment = NSProcessInfo.processInfo.environment;
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *cards = [documents stringByAppendingPathComponent:@"card-a"];
    [NSFileManager.defaultManager createDirectoryAtPath:cards withIntermediateDirectories:YES attributes:nil error:nil];
    setenv("SMS_SAVE_DIR", cards.fileSystemRepresentation, 0);
    setenv("SMS_SETTINGS", [documents stringByAppendingPathComponent:@"settings.txt"].fileSystemRepresentation, 0);
    setenv("XDG_CACHE_HOME", [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
                                 fileSystemRepresentation], 0);
    NSString *disc = environment[@"SUNPAD_DISC"];
    if (!disc || !LoadEngine()) {
        NSLog(@"[harness] no disc (SUNPAD_DISC) or no engine");
        return;
    }
    StartAudio();
    SmsEmbedConfig config = {};
    config.version = SMS_EMBED_VERSION;
    config.discImage = disc.fileSystemRepresentation;
    config.metalLayer = (__bridge void *)layer;
    config.getInstanceProcAddr = (void *)vkGetInstanceProcAddr;
    config.width = width;
    config.height = height;
    NSLog(@"[harness] start: %d", engine.start(&config));
    RunScript(environment[@"SUNPAD_SCRIPT"]);
}
@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [GameController new];
    [self.window makeKeyAndVisible];
}
- (void)sceneWillResignActive:(UIScene *)scene {
    if (engine.pause)
        engine.pause(1);
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    if (engine.pause)
        engine.pause(0);
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation AppDelegate
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
