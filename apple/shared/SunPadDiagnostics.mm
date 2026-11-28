#import "SunPadDiagnostics.h"

#import <TargetConditionals.h>

#import <sys/sysctl.h>

static NSUInteger const SunPadMaximumUniqueRuntimeEvents = 64;

static NSMutableDictionary<NSString *, NSMutableDictionary *> *SunPadRuntimeEvents(void) {
    static NSMutableDictionary<NSString *, NSMutableDictionary *> *events;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        events = [NSMutableDictionary dictionary];
    });
    return events;
}

static NSUInteger SunPadDroppedRuntimeEventKinds = 0;

static NSObject *SunPadDiagnosticsLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static NSString *SunPadDiagnosticsDirectory(void) {
    NSSearchPathDirectory directory = NSApplicationSupportDirectory;
#if TARGET_OS_TV
    // tvOS filesystem-backed state must be treated as purgeable.
    directory = NSCachesDirectory;
#endif
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        directory, NSUserDomainMask, YES);
    NSString *root = [paths.firstObject stringByAppendingPathComponent:@"SunPad"];
    return [root stringByAppendingPathComponent:@"Logs"];
}

NSString *SunPadDiagnosticsLogPath(void) {
    return [SunPadDiagnosticsDirectory() stringByAppendingPathComponent:@"runtime.log"];
}

static NSString *SunPadDiagnosticsPreviousLogPath(void) {
    return [SunPadDiagnosticsDirectory() stringByAppendingPathComponent:@"runtime.previous.log"];
}

static NSString *SunPadRedactedString(NSString *value) {
    NSString *redacted = value ?: @"";
    NSString *temporary = NSTemporaryDirectory();
    if (temporary.length > 1)
        redacted = [redacted stringByReplacingOccurrencesOfString:temporary
                                                       withString:@"<temporary>/"];
    NSString *home = NSHomeDirectory();
    if (home.length > 0)
        redacted = [redacted stringByReplacingOccurrencesOfString:home
                                                       withString:@"<app-container>"];
    return redacted;
}

static NSString *SunPadSingleLine(NSString *value, NSUInteger maximumLength) {
    NSString *single = [[value ?: @"" componentsSeparatedByCharactersInSet:
        NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    single = [single stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (single.length > maximumLength)
        single = [[single substringToIndex:maximumLength] stringByAppendingString:@"…"];
    return SunPadRedactedString(single);
}

// The decompilation engine's stderr (SunPadEngineHost). Absent with the
// compatibility runtime, whose events arrive through SunPadLogRuntimeEvent.
static NSString *SunPadDiagnosticsEngineLogPath(void) {
    return [SunPadDiagnosticsDirectory() stringByAppendingPathComponent:@"Engine.log"];
}

// The engine log's last lines, redacted, for a problem report.
static NSString *SunPadEngineLogTail(NSString *log, NSUInteger maximumLines) {
    NSArray<NSString *> *lines = [log componentsSeparatedByString:@"\n"];
    const NSUInteger start = lines.count > maximumLines ? lines.count - maximumLines : 0;
    NSArray<NSString *> *tail = [lines subarrayWithRange:NSMakeRange(start, lines.count - start)];
    return SunPadRedactedString([tail componentsJoinedByString:@"\n"]);
}

static NSString *SunPadHardwareModel(void) {
    char model[128] = {};
    size_t size = sizeof(model);
    return sysctlbyname("hw.machine", model, &size, nullptr, 0) == 0 && model[0] != '\0'
        ? @(model) : @"unknown";
}

static NSString *SunPadLogTimestamp(void) {
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
        NSISO8601DateFormatWithFractionalSeconds;
    return [formatter stringFromDate:NSDate.date];
}

void SunPadDiagnosticsStart(void) {
    @synchronized (SunPadDiagnosticsLock()) {
        NSFileManager *fileManager = NSFileManager.defaultManager;
        NSString *directory = SunPadDiagnosticsDirectory();
        [fileManager createDirectoryAtPath:directory
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];

        NSString *currentPath = SunPadDiagnosticsLogPath();
        if ([fileManager fileExistsAtPath:currentPath]) {
            NSString *previousPath = SunPadDiagnosticsPreviousLogPath();
            [fileManager removeItemAtPath:previousPath error:nil];
            [fileManager moveItemAtPath:currentPath toPath:previousPath error:nil];
        }
        [SunPadRuntimeEvents() removeAllObjects];
        SunPadDroppedRuntimeEventKinds = 0;
    }

    NSBundle *bundle = NSBundle.mainBundle;
    SunPadLog(@"session start version=%@ build=%@ os=%@",
              [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
              [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown",
              NSProcessInfo.processInfo.operatingSystemVersionString);
    SunPadLog(@"diagnostic schema=2 hardware=%@ processors=%ld physicalMemoryMiB=%.1f",
              SunPadHardwareModel(), (long)NSProcessInfo.processInfo.activeProcessorCount,
              NSProcessInfo.processInfo.physicalMemory / (1024.0 * 1024.0));
}

void SunPadLog(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    message = SunPadRedactedString(message);

    NSLog(@"[SunPad] %@", message);

    NSString *line = [NSString stringWithFormat:@"%@ %@\n", SunPadLogTimestamp(), message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil)
        return;

    @synchronized (SunPadDiagnosticsLock()) {
        NSString *path = SunPadDiagnosticsLogPath();
        NSFileManager *fileManager = NSFileManager.defaultManager;
        if (![fileManager fileExistsAtPath:path])
            [fileManager createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

void SunPadLogRuntimeEvent(NSString *severity, NSString *category, NSString *message) {
    NSString *safeSeverity = SunPadSingleLine(severity, 16);
    NSString *safeCategory = SunPadSingleLine(category, 48);
    NSString *safeMessage = SunPadSingleLine(message, 2000);
    NSString *signature = [NSString stringWithFormat:@"%@|%@|%@",
                           safeSeverity, safeCategory, safeMessage];
    NSUInteger count = 0;
    BOOL shouldLog = NO;
    BOOL firstDroppedKind = NO;
    @synchronized (SunPadDiagnosticsLock()) {
        NSMutableDictionary *event = SunPadRuntimeEvents()[signature];
        if (event == nil) {
            if (SunPadRuntimeEvents().count >= SunPadMaximumUniqueRuntimeEvents) {
                ++SunPadDroppedRuntimeEventKinds;
                firstDroppedKind = SunPadDroppedRuntimeEventKinds == 1;
            } else {
                event = [@{
                    @"severity": safeSeverity,
                    @"category": safeCategory,
                    @"message": safeMessage,
                    @"count": @0,
                } mutableCopy];
                SunPadRuntimeEvents()[signature] = event;
            }
        }
        if (event != nil) {
            count = [event[@"count"] unsignedIntegerValue] + 1;
            event[@"count"] = @(count);
            shouldLog = count == 1 || count == 10 || count == 100 || count % 1000 == 0;
        }
    }
    if (shouldLog) {
        SunPadLog(@"runtime event severity=%@ category=%@ count=%lu message=%@",
                  safeSeverity, safeCategory, (unsigned long)count, safeMessage);
    } else if (firstDroppedKind) {
        SunPadLog(@"runtime event unique-limit=%lu additional kinds will be summarized",
                  (unsigned long)SunPadMaximumUniqueRuntimeEvents);
    }
}

static NSString *SunPadRuntimeEventSummaryLocked(void) {
    NSMutableString *summary = [NSMutableString string];
    NSArray<NSString *> *signatures = [[SunPadRuntimeEvents() allKeys]
        sortedArrayUsingSelector:@selector(compare:)];
    if (signatures.count == 0 && SunPadDroppedRuntimeEventKinds == 0)
        return @"none\n";
    for (NSString *signature in signatures) {
        NSDictionary *event = SunPadRuntimeEvents()[signature];
        [summary appendFormat:@"severity=%@ category=%@ count=%@ message=%@\n",
            event[@"severity"], event[@"category"], event[@"count"], event[@"message"]];
    }
    if (SunPadDroppedRuntimeEventKinds > 0) {
        [summary appendFormat:@"additionalUniqueKinds=%lu\n",
            (unsigned long)SunPadDroppedRuntimeEventKinds];
    }
    return summary;
}

NSURL *SunPadDiagnosticsReportURL(
    NSString *reportID,
    NSDictionary<NSString *, NSString *> *reporterAnswers,
    NSString *technicalContext,
    NSError **error) {
    @synchronized (SunPadDiagnosticsLock()) {
        NSFileManager *fileManager = NSFileManager.defaultManager;
        NSString *current = [NSString stringWithContentsOfFile:SunPadDiagnosticsLogPath()
                                                      encoding:NSUTF8StringEncoding
                                                         error:nil] ?: @"unavailable\n";
        NSString *previous = [NSString stringWithContentsOfFile:SunPadDiagnosticsPreviousLogPath()
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil] ?: @"unavailable\n";
        NSMutableString *report = [NSMutableString string];
        [report appendString:@"SunPad Diagnostic Report v2\n"];
        [report appendFormat:@"reportID=%@\n", SunPadSingleLine(reportID, 80)];
        [report appendFormat:@"generated=%@\n", SunPadLogTimestamp()];
        [report appendString:@"issuesURL=https://github.com/chrissotraidis/sunpad/issues\n\n"];
        [report appendString:@"[Reporter Answers]\n"];
        for (NSString *key in @[@"problem", @"context", @"frequency"]) {
            NSString *value = SunPadSingleLine(reporterAnswers[key], 1000);
            [report appendFormat:@"%@=%@\n", key, value.length > 0 ? value : @"not provided"];
        }
        [report appendString:@"\n[Technical Context]\n"];
        [report appendString:SunPadRedactedString(technicalContext ?: @"unavailable")];
        if (![report hasSuffix:@"\n"])
            [report appendString:@"\n"];
        [report appendString:@"\n[Runtime Warning/Error Summary]\n"];
        [report appendString:SunPadRuntimeEventSummaryLocked()];
        [report appendString:@"\n[Current Session]\n"];
        [report appendString:current];
        if (![report hasSuffix:@"\n"])
            [report appendString:@"\n"];
        [report appendString:@"\n[Previous Session]\n"];
        [report appendString:previous];
        NSString *engineLog = [NSString stringWithContentsOfFile:SunPadDiagnosticsEngineLogPath()
                                                        encoding:NSUTF8StringEncoding
                                                           error:nil];
        if (engineLog != nil) {
            if (![report hasSuffix:@"\n"])
                [report appendString:@"\n"];
            [report appendString:@"\n[Engine Log]\n"];
            [report appendString:SunPadEngineLogTail(engineLog, 200)];
        }

        NSString *documents = [NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        if (documents.length == 0)
            documents = NSTemporaryDirectory();
        NSString *directory = [documents stringByAppendingPathComponent:@"Diagnostics"];
        if (![fileManager createDirectoryAtPath:directory
                    withIntermediateDirectories:YES attributes:nil error:error]) {
            return nil;
        }
        NSString *path = [directory stringByAppendingPathComponent:
                          @"Latest-SunPad-Diagnostic.log"];
        if (![report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error])
            return nil;
        return [NSURL fileURLWithPath:path];
    }
}
