// sunpad-saves: SunPad Next for Mac's save step, the same conversion as on
// iPhone and iPad (apple/shared/SunPadEngineSaves.h).
//   sunpad-saves migrate GCI_FOLDER ENGINE_CARD   the first launch's copy
//   sunpad-saves export ENGINE_CARD GCI_FOLDER    the engine's saves as GCI files
#import <Foundation/Foundation.h>

#import "SunPadEngineSaves.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 4) {
            fprintf(stderr, "usage: sunpad-saves migrate GCI_FOLDER ENGINE_CARD | export ENGINE_CARD GCI_FOLDER\n");
            return 2;
        }
        NSString *command = @(argv[1]);
        NSString *from = @(argv[2]);
        NSString *to = @(argv[3]);
        NSError *error = nil;
        BOOL ok = NO;
        if ([command isEqualToString:@"migrate"])
            ok = SunPadMigrateGCIFolderToEngineCard(from, to, &error);
        else if ([command isEqualToString:@"export"])
            ok = SunPadEngineCardToGCIFolder(from, to, &error);
        if (!ok)
            fprintf(stderr, "sunpad-saves: %s\n", error.localizedDescription.UTF8String ?: "unknown command");
        return ok ? 0 : 1;
    }
}
