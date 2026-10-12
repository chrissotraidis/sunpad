#import <Foundation/Foundation.h>

#include <cassert>
#include <cstring>
#include <iostream>

#include "SunPadSaveTransfer.h"

// Synthetic saves only. Real player saves never belong in the repository.
static NSData *MakeSave(const char *game, const char *maker, const char *name,
                        uint16_t blocks, uint8_t fill) {
    NSMutableData *data = [NSMutableData dataWithLength:0x40 + blocks * 0x2000];
    uint8_t *bytes = static_cast<uint8_t *>(data.mutableBytes);
    memset(bytes + 0x40, fill, blocks * 0x2000);
    memcpy(bytes, game, 4);
    memcpy(bytes + 4, maker, 2);
    memcpy(bytes + 8, name, strlen(name));
    bytes[0x38] = static_cast<uint8_t>(blocks >> 8);
    bytes[0x39] = static_cast<uint8_t>(blocks & 0xff);
    return data;
}

static NSData *Read(NSString *path) {
    return [NSData dataWithContentsOfFile:path];
}

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *root = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSString *card = [root stringByAppendingPathComponent:@"GC/USA/Card A"];
        NSString *staging = [root stringByAppendingPathComponent:@"SaveImport/pending.gci"];
        NSString *backups = [root stringByAppendingPathComponent:@"Save Backups"];

        NSData *imported = MakeSave("GMSE", "01", "super_mario_sunshine", 3, 0xA1);
        NSError *error = nil;
        assert([SunPadValidateGMSE01Save(imported, &error)
            isEqualToString:@"01-GMSE-super_mario_sunshine.gci"]);

        // Rejections leave nothing staged.
        assert(SunPadValidateGMSE01Save(MakeSave("GZLE", "01", "zelda", 3, 0), &error) == nil);
        assert(error.localizedDescription.length > 0);
        assert(SunPadValidateGMSE01Save(MakeSave("GMSE", "8P", "super_mario_sunshine", 3, 0), nil) == nil);
        NSMutableData *truncated = [imported mutableCopy];
        truncated.length -= 1;
        assert(SunPadValidateGMSE01Save(truncated, nil) == nil);
        assert(SunPadValidateGMSE01Save([NSData dataWithBytes:"GMSE01" length:6], nil) == nil);
        assert(SunPadValidateGMSE01Save(MakeSave("GMSE", "01", "super_mario_sunshine", 0, 0), nil) == nil);
        assert(SunPadValidateGMSE01Save(MakeSave("GMSE", "01", "", 3, 0), nil) == nil);
        assert(!SunPadStageSaveImport(truncated, staging, nil));
        assert(![fm fileExistsAtPath:staging]);

        // Nothing staged: nothing happens and no backup is made.
        NSString *backup = nil;
        assert(SunPadApplyStagedSaveImport(staging, card, backups, [NSDate date], &backup, nil) ==
               SunPadSaveImportNothingPending);
        assert(backup == nil && ![fm fileExistsAtPath:backups]);

        // Existing card: the same save under another file name, plus an
        // unrelated save and a non-save file.
        [fm createDirectoryAtPath:card withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *oldSave = MakeSave("GMSE", "01", "super_mario_sunshine", 3, 0x11);
        NSData *otherSave = MakeSave("GMSE", "01", "another_save", 1, 0x22);
        [oldSave writeToFile:[card stringByAppendingPathComponent:@"renamed.gci"] atomically:YES];
        [otherSave writeToFile:[card stringByAppendingPathComponent:@"01-GMSE-another_save.gci"]
                    atomically:YES];
        [@"note" writeToFile:[card stringByAppendingPathComponent:@"notes.txt"]
                  atomically:YES encoding:NSUTF8StringEncoding error:nil];

        assert(SunPadStageSaveImport(imported, staging, &error));
        assert([Read(staging) isEqualToData:imported]);
        // Applying copies the card to a backup first, then replaces only the
        // save with the same identity.
        assert(SunPadApplyStagedSaveImport(staging, card, backups, [NSDate date], &backup, &error) ==
               SunPadSaveImportApplied);
        assert(backup != nil);
        assert([Read([backup stringByAppendingPathComponent:@"renamed.gci"]) isEqualToData:oldSave]);
        assert([Read([backup stringByAppendingPathComponent:@"01-GMSE-another_save.gci"])
            isEqualToData:otherSave]);
        assert([fm fileExistsAtPath:[backup stringByAppendingPathComponent:@"notes.txt"]]);
        assert(![fm fileExistsAtPath:[card stringByAppendingPathComponent:@"renamed.gci"]]);
        assert([Read([card stringByAppendingPathComponent:@"01-GMSE-super_mario_sunshine.gci"])
            isEqualToData:imported]);
        assert([Read([card stringByAppendingPathComponent:@"01-GMSE-another_save.gci"])
            isEqualToData:otherSave]);
        assert(![fm fileExistsAtPath:[card stringByAppendingPathComponent:@"SunPad import.tmp"]]);
        assert(![fm fileExistsAtPath:staging]);

        // A second launch finds nothing pending.
        assert(SunPadApplyStagedSaveImport(staging, card, backups, [NSDate date], &backup, nil) ==
               SunPadSaveImportNothingPending);

        // Two imports in the same second get separate backup folders.
        NSDate *fixed = [NSDate dateWithTimeIntervalSince1970:1800000000];
        NSString *first = nil, *second = nil;
        assert(SunPadStageSaveImport(imported, staging, nil));
        assert(SunPadApplyStagedSaveImport(staging, card, backups, fixed, &first, nil) ==
               SunPadSaveImportApplied);
        assert(SunPadStageSaveImport(oldSave, staging, nil));
        assert(SunPadApplyStagedSaveImport(staging, card, backups, fixed, &second, nil) ==
               SunPadSaveImportApplied);
        assert(first != nil && second != nil && ![first isEqualToString:second]);
        assert([Read([second stringByAppendingPathComponent:@"01-GMSE-super_mario_sunshine.gci"])
            isEqualToData:imported]);
        assert([Read([card stringByAppendingPathComponent:@"01-GMSE-super_mario_sunshine.gci"])
            isEqualToData:oldSave]);

        // A damaged staged file is discarded without touching the card.
        [truncated writeToFile:staging atomically:YES];
        assert(SunPadApplyStagedSaveImport(staging, card, backups, [NSDate date], &backup, &error) ==
               SunPadSaveImportFailed);
        assert(![fm fileExistsAtPath:staging]);
        assert([Read([card stringByAppendingPathComponent:@"01-GMSE-super_mario_sunshine.gci"])
            isEqualToData:oldSave]);

        // Export copies valid saves only.
        [@"partial" writeToFile:[card stringByAppendingPathComponent:@"broken.gci"]
                     atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *exportDir = [root stringByAppendingPathComponent:@"Export"];
        NSArray<NSURL *> *exported = SunPadCopySavesForExport(card, exportDir, &error);
        assert(exported.count == 2);
        for (NSURL *url in exported)
            assert(SunPadValidateGMSE01Save(Read(url.path), nil) != nil);
        NSString *emptyCard = [root stringByAppendingPathComponent:@"Empty"];
        assert(SunPadCopySavesForExport(emptyCard, exportDir, &error) == nil);
        assert(error.localizedDescription.length > 0);

        [fm removeItemAtPath:root error:nil];
        std::cout << "SunPad save transfer regression test passed\n";
    }
    return 0;
}
