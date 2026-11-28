#import "SunPadEngineSaves.h"
#import "SunPadSaveTransfer.h"

#include <cassert>
#include <cstring>

// A GMSE01 save as Dolphin writes it: the 64-byte entry, then two blocks.
static NSData *Save(const char *name, uint16_t firstBlock, uint8_t fill) {
    NSMutableData *gci = [NSMutableData dataWithLength:0x40 + 2 * 0x2000];
    uint8_t *b = static_cast<uint8_t *>(gci.mutableBytes);
    memcpy(b, "GMSE01", 6);
    b[0x06] = 0xFF;
    b[0x07] = 0x02;
    strncpy(reinterpret_cast<char *>(b + 0x08), name, 32);
    b[0x28] = 0x12; b[0x29] = 0x34; b[0x2A] = 0x56; b[0x2B] = 0x78;   // time
    b[0x2C] = 0x00; b[0x2D] = 0x00; b[0x2E] = 0x00; b[0x2F] = 0x40;   // icon address
    b[0x30] = 0x00; b[0x31] = 0x05;                                   // icon format
    b[0x32] = 0x00; b[0x33] = 0x0F;                                   // icon speed
    b[0x34] = 0x04; b[0x35] = 0x03;                                   // permission, copies
    b[0x36] = firstBlock >> 8; b[0x37] = firstBlock & 0xFF;
    b[0x38] = 0x00; b[0x39] = 0x02;                                   // two blocks
    b[0x3A] = 0xFF; b[0x3B] = 0xFF;
    b[0x3C] = 0x00; b[0x3D] = 0x00; b[0x3E] = 0x00; b[0x3F] = 0x00;   // comment address
    for (NSUInteger i = 0x40; i < gci.length; ++i)
        b[i] = uint8_t(fill + i * 7);
    return gci;
}

int main() {
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *dolphin = [root stringByAppendingPathComponent:@"Card A"];
        NSString *engine = [root stringByAppendingPathComponent:@"card-a"];
        NSString *back = [root stringByAppendingPathComponent:@"Card A again"];
        [fm createDirectoryAtPath:dolphin withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *first = Save("super_mario_sunshine", 9, 0x11);
        NSData *other = Save("sms_extra", 5, 0x22);
        NSString *firstName = SunPadValidateGMSE01Save(first, nil);
        NSString *otherName = SunPadValidateGMSE01Save(other, nil);
        assert(firstName && otherName);
        [first writeToFile:[dolphin stringByAppendingPathComponent:firstName] atomically:YES];
        [other writeToFile:[dolphin stringByAppendingPathComponent:otherName] atomically:YES];

        NSError *error = nil;
        assert(SunPadMigrateGCIFolderToEngineCard(dolphin, engine, &error));
        NSString *index = [NSString stringWithContentsOfFile:[engine stringByAppendingPathComponent:@"index.txt"]
                                                    encoding:NSUTF8StringEncoding error:nil];
        assert([index isEqualToString:@"sms_extra\nsuper_mario_sunshine"]);
        NSData *dat = [NSData dataWithContentsOfFile:[engine stringByAppendingPathComponent:@"super_mario_sunshine.dat"]];
        assert([dat isEqualToData:[first subdataWithRange:NSMakeRange(0x40, 2 * 0x2000)]]);
        NSData *stat = [NSData dataWithContentsOfFile:[engine stringByAppendingPathComponent:@"super_mario_sunshine.stat"]];
        assert(stat.length == 0x6C);
        const uint8_t *s = static_cast<const uint8_t *>(stat.bytes);
        assert(strcmp(reinterpret_cast<const char *>(s), "super_mario_sunshine") == 0);
        assert(s[0x20] == 0x00 && s[0x21] == 0x40 && s[0x22] == 0 && s[0x23] == 0);   // length 0x4000, little-endian
        assert(s[0x24] == 0x78 && s[0x27] == 0x12);                                   // time
        assert(memcmp(s + 0x28, "GMSE", 4) == 0 && memcmp(s + 0x2C, "01", 2) == 0);
        assert(s[0x2E] == 0x02 && s[0x30] == 0x40 && s[0x34] == 0x05 && s[0x36] == 0x0F);

        // The Dolphin folder is never changed by migration, and a second migration does nothing.
        assert([[NSData dataWithContentsOfFile:[dolphin stringByAppendingPathComponent:firstName]] isEqualToData:first]);
        [fm removeItemAtPath:[engine stringByAppendingPathComponent:@"sms_extra.dat"] error:nil];
        assert(SunPadMigrateGCIFolderToEngineCard(dolphin, engine, &error));
        assert(![fm fileExistsAtPath:[engine stringByAppendingPathComponent:@"sms_extra.dat"]]);
        assert(SunPadGCIFolderToEngineCard(dolphin, engine, &error));

        // Back to GCI byte for byte.
        assert(SunPadEngineCardToGCIFolder(engine, back, &error));
        assert([[NSData dataWithContentsOfFile:[back stringByAppendingPathComponent:firstName]] isEqualToData:first]);
        assert([[NSData dataWithContentsOfFile:[back stringByAppendingPathComponent:otherName]] isEqualToData:other]);

        // A save the engine made has no kept entry: Dolphin's defaults fill the rest.
        [fm removeItemAtPath:[engine stringByAppendingPathComponent:@"super_mario_sunshine.direntry"] error:nil];
        assert(SunPadEngineCardToGCIFolder(engine, back, &error));
        NSData *made = [NSData dataWithContentsOfFile:[back stringByAppendingPathComponent:firstName]];
        const uint8_t *m = static_cast<const uint8_t *>(made.bytes);
        assert(m[0x34] == 0x04 && m[0x35] == 0x00 && m[0x36] == 0x00 && m[0x37] == 0x05);
        assert(memcmp(m + 0x38, static_cast<const uint8_t *>(first.bytes) + 0x38, 2) == 0);
        assert(memcmp(m + 0x40, static_cast<const uint8_t *>(first.bytes) + 0x40, 2 * 0x2000) == 0);

        // Rebuilding the card drops saves the folder no longer has.
        [fm removeItemAtPath:[dolphin stringByAppendingPathComponent:otherName] error:nil];
        assert(SunPadGCIFolderToEngineCard(dolphin, engine, &error));
        assert(![fm fileExistsAtPath:[engine stringByAppendingPathComponent:@"sms_extra.dat"]]);
        [fm removeItemAtPath:root error:nil];
    }
    return 0;
}
