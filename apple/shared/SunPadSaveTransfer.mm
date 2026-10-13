#import "SunPadSaveTransfer.h"

NSErrorDomain const SunPadSaveTransferErrorDomain = @"SunPadSaveTransfer";

namespace {

constexpr NSUInteger kEntrySize = 0x40;
constexpr NSUInteger kBlockSize = 0x2000;
constexpr NSUInteger kMaximumBlocks = 2043;
constexpr NSUInteger kFilenameOffset = 0x08;
constexpr NSUInteger kFilenameLength = 32;
constexpr NSUInteger kBlockCountOffset = 0x38;

BOOL Fail(NSError **error, NSString *message) {
    if (error != nullptr) {
        *error = [NSError errorWithDomain:SunPadSaveTransferErrorDomain
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

// Game code, maker code and internal filename: the identity Dolphin uses to
// refuse a second copy of the same save.
NSData *Identity(NSData *data) {
    if (data.length < kEntrySize)
        return nil;
    NSMutableData *identity = [NSMutableData dataWithData:[data subdataWithRange:NSMakeRange(0, 6)]];
    [identity appendData:[data subdataWithRange:NSMakeRange(kFilenameOffset, kFilenameLength)]];
    return identity;
}

NSString *InternalName(NSData *data) {
    const uint8_t *bytes = static_cast<const uint8_t *>(data.bytes) + kFilenameOffset;
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i = 0; i < kFilenameLength && bytes[i] != 0; ++i) {
        unichar c = bytes[i];
        BOOL safe = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.';
        [name appendFormat:@"%C", safe ? c : (unichar)'_'];
    }
    return name;
}

NSArray<NSString *> *GCIFiles(NSString *directory) {
    NSArray<NSString *> *entries =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] ?: @[];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *entry in [entries sortedArrayUsingSelector:@selector(compare:)]) {
        if ([entry.pathExtension.lowercaseString isEqualToString:@"gci"])
            [files addObject:[directory stringByAppendingPathComponent:entry]];
    }
    return files;
}

NSString *NewBackupFolder(NSString *backupsRoot, NSDate *now, NSError **error) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone localTimeZone];
    formatter.dateFormat = @"yyyy-MM-dd HHmmss";
    NSString *base = [NSString stringWithFormat:@"%@ before import",
                                                [formatter stringFromDate:now]];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager createDirectoryAtPath:backupsRoot
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:error])
        return nil;
    for (NSUInteger attempt = 1; attempt < 100; ++attempt) {
        NSString *name = attempt == 1 ? base : [NSString stringWithFormat:@"%@ %lu", base,
                                                                  (unsigned long)attempt];
        NSString *path = [backupsRoot stringByAppendingPathComponent:name];
        if ([fileManager createDirectoryAtPath:path withIntermediateDirectories:NO
                                    attributes:nil error:nil])
            return path;
    }
    Fail(error, @"SunPad could not create a save backup folder.");
    return nil;
}

} // namespace

NSString *SunPadValidateGMSE01Save(NSData *data, NSError **error) {
    if (data.length < kEntrySize) {
        Fail(error, @"This file is too small to be a GameCube save.");
        return nil;
    }
    const uint8_t *bytes = static_cast<const uint8_t *>(data.bytes);
    if (memcmp(bytes, "GMSE", 4) != 0 || memcmp(bytes + 4, "01", 2) != 0) {
        Fail(error, @"This is not a North American Super Mario Sunshine (GMSE01) save.");
        return nil;
    }
    NSUInteger blocks = (static_cast<NSUInteger>(bytes[kBlockCountOffset]) << 8) |
                        bytes[kBlockCountOffset + 1];
    if (blocks == 0 || blocks > kMaximumBlocks || data.length != kEntrySize + blocks * kBlockSize) {
        Fail(error, @"This save file is incomplete or damaged. Export it again from Dolphin's Memory Card Manager as a .gci file.");
        return nil;
    }
    NSString *name = InternalName(data);
    if (name.length == 0) {
        Fail(error, @"This save file has no internal name and cannot be imported.");
        return nil;
    }
    return [NSString stringWithFormat:@"01-GMSE-%@.gci", name];
}

BOOL SunPadStageSaveImport(NSData *data, NSString *stagingPath, NSError **error) {
    if (SunPadValidateGMSE01Save(data, error) == nil)
        return NO;
    if (![[NSFileManager defaultManager]
            createDirectoryAtPath:stagingPath.stringByDeletingLastPathComponent
      withIntermediateDirectories:YES
                       attributes:nil
                            error:error])
        return NO;
    return [data writeToFile:stagingPath options:NSDataWritingAtomic error:error];
}

SunPadSaveImportResult SunPadApplyStagedSaveImport(NSString *stagingPath,
                                                   NSString *cardDirectory,
                                                   NSString *backupsRoot,
                                                   NSDate *now,
                                                   NSString **backupPath,
                                                   NSError **error) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (backupPath != nullptr)
        *backupPath = nil;
    if (![fileManager fileExistsAtPath:stagingPath])
        return SunPadSaveImportNothingPending;

    NSData *data = [NSData dataWithContentsOfFile:stagingPath options:0 error:error];
    NSString *fileName = data != nil ? SunPadValidateGMSE01Save(data, error) : nil;
    if (fileName == nil) {
        // The staged file is SunPad's own copy; the player's original is untouched.
        [fileManager removeItemAtPath:stagingPath error:nil];
        return SunPadSaveImportFailed;
    }
    if (![fileManager createDirectoryAtPath:cardDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:error])
        return SunPadSaveImportFailed;

    NSArray<NSString *> *entries = [fileManager contentsOfDirectoryAtPath:cardDirectory error:error];
    if (entries == nil)
        return SunPadSaveImportFailed;

    // Back up everything first. Nothing in the card changes unless this works.
    NSString *backup = NewBackupFolder(backupsRoot, now, error);
    if (backup == nil)
        return SunPadSaveImportFailed;
    NSData *identity = Identity(data);
    NSString *destination = [cardDirectory stringByAppendingPathComponent:fileName];
    NSMutableArray<NSString *> *replacedFiles = [NSMutableArray array];
    for (NSString *entry in entries) {
        NSString *source = [cardDirectory stringByAppendingPathComponent:entry];
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:source error:error];
        if (attributes == nil)
            return SunPadSaveImportFailed;
        if ([attributes[NSFileType] isEqualToString:NSFileTypeDirectory])
            continue;
        if (![fileManager copyItemAtPath:source
                                  toPath:[backup stringByAppendingPathComponent:entry]
                                   error:error])
            return SunPadSaveImportFailed;
        if (![entry.pathExtension.lowercaseString isEqualToString:@"gci"])
            continue;
        NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:source]
                                                                error:error];
        if (handle == nil)
            return SunPadSaveImportFailed;
        NSData *header = [handle readDataUpToLength:kEntrySize error:error];
        [handle closeFile];
        if (header == nil)
            return SunPadSaveImportFailed;
        BOOL sameSave = [Identity(header) isEqualToData:identity];
        BOOL sameName = [entry caseInsensitiveCompare:fileName] == NSOrderedSame;
        if (sameSave || sameName)
            [replacedFiles addObject:source];
        // On a case-insensitive volume, a differently cased name can refer to
        // the replacement itself. Reuse that exact path so cleanup keeps it.
        if (sameName && (![entries containsObject:fileName] || [entry isEqualToString:fileName]))
            destination = source;
    }
    if (backupPath != nullptr)
        *backupPath = backup;

    // Commit the replacement before removing any playable save. Atomic writing
    // keeps the existing destination intact if the write or rename fails.
    if (![data writeToFile:destination options:NSDataWritingAtomic error:error])
        return SunPadSaveImportFailed;
    for (NSString *path in replacedFiles) {
        if (![path isEqualToString:destination] && ![fileManager removeItemAtPath:path error:error])
            return SunPadSaveImportFailed;
    }
    if (![fileManager removeItemAtPath:stagingPath error:error])
        return SunPadSaveImportFailed;
    return SunPadSaveImportApplied;
}

NSArray<NSURL *> *SunPadCopySavesForExport(NSString *cardDirectory,
                                           NSString *destination,
                                           NSError **error) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:destination error:nil];
    if (![fileManager createDirectoryAtPath:destination
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:error])
        return nil;
    NSMutableArray<NSURL *> *exported = [NSMutableArray array];
    for (NSString *path in GCIFiles(cardDirectory)) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        // A save Dolphin is still writing fails validation and is skipped.
        if (data == nil || SunPadValidateGMSE01Save(data, nil) == nil)
            continue;
        NSString *target = [destination stringByAppendingPathComponent:path.lastPathComponent];
        if (![data writeToFile:target options:NSDataWritingAtomic error:error])
            return nil;
        [exported addObject:[NSURL fileURLWithPath:target]];
    }
    if (exported.count == 0) {
        Fail(error, @"There are no Super Mario Sunshine saves to export yet. Save in the game first.");
        return nil;
    }
    return exported;
}
