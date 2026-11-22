#import <Foundation/Foundation.h>

#include <cassert>
#include <iostream>

#import "SunPadDiagnostics.h"

int main(void) {
    @autoreleasepool {
        SunPadDiagnosticsStart();
        SunPadLog(@"previous session sentinel");

        // A new launch retains exactly the preceding session for reports.
        SunPadDiagnosticsStart();
        SunPadLog(@"current session sentinel");
        NSString *homePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/SunPad"];
        NSString *temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"import.iso"];
        SunPadLog(@"private paths home=%@ temporary=%@", homePath, temporaryPath);
        for (NSUInteger index = 0; index < 11; ++index) {
            SunPadLogRuntimeEvent(@"warning", @"host-gpu",
                                  @"repeated Metal diagnostic sentinel");
        }

        // The decompilation engine's log, as SunPadEngineHost writes it.
        NSString *engineLog = [[SunPadDiagnosticsLogPath() stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"Engine.log"];
        NSMutableString *engineLines = [NSMutableString stringWithString:@"[engine] dropped first line\n"];
        for (NSUInteger index = 0; index < 200; ++index)
            [engineLines appendFormat:@"[card] slot A: %@/card-a %lu\n", homePath, (unsigned long)index];
        [engineLines writeToFile:engineLog atomically:YES encoding:NSUTF8StringEncoding error:nil];

        NSError *error = nil;
        NSString *contents = [NSString stringWithContentsOfFile:SunPadDiagnosticsLogPath()
                                                        encoding:NSUTF8StringEncoding
                                                           error:&error];
        assert(contents != nil);
        assert(error == nil);
        assert([contents containsString:@"current session sentinel"]);
        assert(![contents containsString:@"previous session sentinel"]);
        assert([contents containsString:@"session start version="]);
        assert(![contents containsString:NSHomeDirectory()]);
        assert(![contents containsString:NSTemporaryDirectory()]);
        // The test home itself lives below the temporary directory, so the
        // more specific temporary-directory redaction legitimately wins.
        assert([contents containsString:@"home/Library/SunPad"]);
        assert([contents containsString:@"<temporary>/import.iso"]);

        NSDictionary<NSString *, NSString *> *answers = @{
            @"problem": @"The picture warped after entering the plaza.",
            @"context": @"Experimental mode at 4x\nthen took a screenshot",
            @"frequency": @"Once",
        };
        NSString *technical = [NSString stringWithFormat:
            @"performanceProfile=experimental-90-qos\nprivate=%@", homePath];
        NSURL *reportURL = SunPadDiagnosticsReportURL(
            @"SP-TEST123", answers, technical, &error);
        assert(reportURL != nil);
        assert(error == nil);
        assert([reportURL.lastPathComponent isEqualToString:
                @"Latest-SunPad-Diagnostic.log"]);
        NSString *report = [NSString stringWithContentsOfURL:reportURL
                                                    encoding:NSUTF8StringEncoding
                                                       error:&error];
        assert(report != nil);
        assert(error == nil);
        assert([report containsString:@"SunPad Diagnostic Report v2"]);
        assert([report containsString:@"reportID=SP-TEST123"]);
        assert([report containsString:@"issuesURL=https://github.com/chrissotraidis/sunpad/issues"]);
        assert([report containsString:@"problem=The picture warped after entering the plaza."]);
        assert([report containsString:@"context=Experimental mode at 4x then took a screenshot"]);
        assert([report containsString:@"performanceProfile=experimental-90-qos"]);
        assert([report containsString:@"category=host-gpu count=11"]);
        assert([report containsString:@"[Current Session]"]);
        assert([report containsString:@"current session sentinel"]);
        assert([report containsString:@"[Previous Session]"]);
        assert([report containsString:@"previous session sentinel"]);
        assert(![report containsString:NSHomeDirectory()]);
        assert(![report containsString:NSTemporaryDirectory()]);
        assert([report containsString:@"[Engine Log]"]);
        assert([report containsString:@"/card-a 199"]);
        assert(![report containsString:@"dropped first line"]);

        std::cout << "SunPad guided diagnostic report tests passed\n";
    }
    return 0;
}
