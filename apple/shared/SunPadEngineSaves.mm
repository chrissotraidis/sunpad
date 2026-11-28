#import "SunPadEngineSaves.h"
#import "SunPadSaveTransfer.h"

#include <cstring>

namespace {

constexpr NSUInteger kEntrySize = 0x40;    // a GCI file's directory entry (CARDDir, big-endian)
constexpr NSUInteger kStatSize = 0x6C;     // the SDK's CARDStat
constexpr NSUInteger kBlockSize = 0x2000;

BOOL Fail(NSError **error, NSString *message) {
    if (error != nullptr)
        *error = [NSError errorWithDomain:SunPadSaveTransferErrorDomain
                                     code:2
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

uint32_t BigEndian32(const uint8_t *p) { return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3]; }
uint16_t BigEndian16(const uint8_t *p) { return uint16_t(p[0] << 8 | p[1]); }
void PutBigEndian32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
void PutBigEndian16(uint8_t *p, uint16_t v) { p[0] = v >> 8; p[1] = v; }
uint32_t Little32(const uint8_t *p) { return uint32_t(p[3]) << 24 | uint32_t(p[2]) << 16 | uint32_t(p[1]) << 8 | p[0]; }
uint16_t Little16(const uint8_t *p) { return uint16_t(p[1] << 8 | p[0]); }
void PutLittle32(uint8_t *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
void PutLittle16(uint8_t *p, uint16_t v) { p[0] = v; p[1] = v >> 8; }

// The engine's file name on disk (platform/card's safe()): letters, digits,
// '_', '-' and '.' stay, anything else becomes '_'. GMSE01's files keep their
// plain names.
NSString *DiskName(const uint8_t *fileName) {
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i = 0; i < 32 && fileName[i] != 0; ++i) {
        const unichar c = fileName[i];
        const BOOL kept = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
                          c == '_' || c == '-' || c == '.';
        [name appendFormat:@"%C", kept ? c : (unichar)'_'];
    }
    return name;
}

// The GCI entry's fields in a CARDStat, as the engine keeps it.
NSData *StatFromEntry(const uint8_t *entry) {
    NSMutableData *stat = [NSMutableData dataWithLength:kStatSize];
    uint8_t *s = static_cast<uint8_t *>(stat.mutableBytes);
    memcpy(s + 0x00, entry + 0x08, 32);                               // fileName
    PutLittle32(s + 0x20, uint32_t(BigEndian16(entry + 0x38)) * kBlockSize);  // length
    PutLittle32(s + 0x24, BigEndian32(entry + 0x28));                 // time
    memcpy(s + 0x28, entry + 0x00, 4);                                // gameName
    memcpy(s + 0x2C, entry + 0x04, 2);                                // company
    s[0x2E] = entry[0x07];                                            // bannerFormat
    PutLittle32(s + 0x30, BigEndian32(entry + 0x2C));                 // iconAddr
    PutLittle16(s + 0x34, BigEndian16(entry + 0x30));                 // iconFormat
    PutLittle16(s + 0x36, BigEndian16(entry + 0x32));                 // iconSpeed
    PutLittle32(s + 0x38, BigEndian32(entry + 0x3C));                 // commentAddr
    return stat;
}

// A GCI entry from a CARDStat. The fields a CARDStat lacks come from the
// file's kept entry when it has one, else from Dolphin's defaults for a file
// alone on a card.
NSData *EntryFromStat(const uint8_t *s, NSData *kept) {
    NSMutableData *entry = [NSMutableData dataWithLength:kEntrySize];
    uint8_t *e = static_cast<uint8_t *>(entry.mutableBytes);
    e[0x06] = 0xFF;
    e[0x34] = 0x04;                  // permission: public
    PutBigEndian16(e + 0x36, 5);     // first block
    e[0x3A] = e[0x3B] = 0xFF;
    if (kept.length == kEntrySize)
        memcpy(e, kept.bytes, kEntrySize);
    memcpy(e + 0x00, s + 0x28, 4);
    memcpy(e + 0x04, s + 0x2C, 2);
    e[0x07] = s[0x2E];
    memcpy(e + 0x08, s + 0x00, 32);
    PutBigEndian32(e + 0x28, Little32(s + 0x24));
    PutBigEndian32(e + 0x2C, Little32(s + 0x30));
    PutBigEndian16(e + 0x30, Little16(s + 0x34));
    PutBigEndian16(e + 0x32, Little16(s + 0x36));
    PutBigEndian16(e + 0x38, uint16_t(Little32(s + 0x20) / kBlockSize));
    PutBigEndian32(e + 0x3C, Little32(s + 0x38));
    return entry;
}

NSArray<NSString *> *IndexNames(NSString *engineCard) {
    NSString *text = [NSString stringWithContentsOfFile:[engineCard stringByAppendingPathComponent:@"index.txt"]
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    return text ? [text componentsSeparatedByString:@"\n"] : nil;
}

BOOL Write(NSData *data, NSString *path, NSError **error) {
    if ([data writeToFile:path options:NSDataWritingAtomic error:error])
        return YES;
    return Fail(error, [NSString stringWithFormat:@"SunPad could not write %@.", path.lastPathComponent]);
}

}  // namespace

BOOL SunPadEngineCardToGCIFolder(NSString *engineCard, NSString *gciFolder, NSError **error) {
    NSArray<NSString *> *names = IndexNames(engineCard);
    if (names == nil)
        return YES;  // no saves yet
    if (![NSFileManager.defaultManager createDirectoryAtPath:gciFolder withIntermediateDirectories:YES
                                                  attributes:nil error:error])
        return NO;
    for (NSString *name in names) {
        if (name.length == 0)
            continue;
        NSString *base = [engineCard stringByAppendingPathComponent:name];
        NSData *data = [NSData dataWithContentsOfFile:[base stringByAppendingPathExtension:@"dat"]];
        NSData *stat = [NSData dataWithContentsOfFile:[base stringByAppendingPathExtension:@"stat"]];
        if (data == nil || stat.length != kStatSize)
            continue;
        NSData *kept = [NSData dataWithContentsOfFile:[base stringByAppendingPathExtension:@"direntry"]];
        NSMutableData *gci = [NSMutableData dataWithData:EntryFromStat(static_cast<const uint8_t *>(stat.bytes), kept)];
        [gci appendData:data];
        NSString *fileName = SunPadValidateGMSE01Save(gci, nil);
        if (fileName == nil)
            continue;  // another game's file, or one the GCI folder cannot hold
        if (!Write(gci, [gciFolder stringByAppendingPathComponent:fileName], error))
            return NO;
    }
    return YES;
}

BOOL SunPadGCIFolderToEngineCard(NSString *gciFolder, NSString *engineCard, NSError **error) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (![fileManager createDirectoryAtPath:engineCard withIntermediateDirectories:YES attributes:nil error:error])
        return NO;
    NSArray<NSString *> *entries =
        [[fileManager contentsOfDirectoryAtPath:gciFolder error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *entry in entries) {
        if (![entry.pathExtension.lowercaseString isEqualToString:@"gci"])
            continue;
        NSData *gci = [NSData dataWithContentsOfFile:[gciFolder stringByAppendingPathComponent:entry]];
        if (gci == nil || SunPadValidateGMSE01Save(gci, nil) == nil)
            continue;
        const uint8_t *bytes = static_cast<const uint8_t *>(gci.bytes);
        NSString *name = DiskName(bytes + 0x08);
        if (name.length == 0 || [names containsObject:name])
            continue;  // as Dolphin, the first copy of a save wins
        NSString *base = [engineCard stringByAppendingPathComponent:name];
        if (!Write([gci subdataWithRange:NSMakeRange(kEntrySize, gci.length - kEntrySize)],
                   [base stringByAppendingPathExtension:@"dat"], error) ||
            !Write(StatFromEntry(bytes), [base stringByAppendingPathExtension:@"stat"], error) ||
            !Write([gci subdataWithRange:NSMakeRange(0, kEntrySize)],
                   [base stringByAppendingPathExtension:@"direntry"], error))
            return NO;
        [names addObject:name];
    }
    // The index is the card: the files it no longer names are no longer saves.
    NSData *index = [[names componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (!Write(index, [engineCard stringByAppendingPathComponent:@"index.txt"], error))
        return NO;
    for (NSString *entry in [fileManager contentsOfDirectoryAtPath:engineCard error:nil]) {
        NSString *extension = entry.pathExtension;
        if (([extension isEqualToString:@"dat"] || [extension isEqualToString:@"stat"] ||
             [extension isEqualToString:@"direntry"]) &&
            ![names containsObject:entry.stringByDeletingPathExtension])
            [fileManager removeItemAtPath:[engineCard stringByAppendingPathComponent:entry] error:nil];
    }
    return YES;
}

BOOL SunPadMigrateGCIFolderToEngineCard(NSString *gciFolder, NSString *engineCard, NSError **error) {
    if (IndexNames(engineCard) != nil)
        return YES;
    return SunPadGCIFolderToEngineCard(gciFolder, engineCard, error);
}
