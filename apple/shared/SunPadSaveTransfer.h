#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* Moves GameCube saves between SunPad's Dolphin GCI folder and the player.
 *
 * Dolphin's GCI-folder backend loads every .gci in the card folder whose game
 * code matches, skips a second file with the same maker, game code and
 * internal filename, and requires the file to be exactly the 64-byte entry
 * plus 8 KiB per block. Imports follow the same rules. They are staged and
 * applied only before the runtime opens the card, after the current saves are
 * copied to a backup folder. */

extern NSErrorDomain const SunPadSaveTransferErrorDomain;

typedef NS_ENUM(NSInteger, SunPadSaveImportResult) {
    SunPadSaveImportNothingPending = 0,
    SunPadSaveImportApplied = 1,
    SunPadSaveImportFailed = 2,
};

/* Returns the Dolphin-style file name ("01-GMSE-<name>.gci") for a valid
 * GMSE01 save, or nil with a player-readable error. */
NSString *_Nullable SunPadValidateGMSE01Save(NSData *data, NSError **error);

/* Validates data and writes it to stagingPath, replacing an earlier staged
 * import. The card folder is not touched. */
BOOL SunPadStageSaveImport(NSData *data, NSString *stagingPath, NSError **error);

/* Applies a staged import. Copies every file in cardDirectory into a new
 * dated folder under backupsRoot, atomically writes the replacement, then
 * removes other saves with the same identity. A failed replacement leaves the
 * current card saves intact. Call only while the runtime is not using the card.
 * backupPath receives the backup folder when one was made. */
SunPadSaveImportResult SunPadApplyStagedSaveImport(NSString *stagingPath,
                                                   NSString *cardDirectory,
                                                   NSString *backupsRoot,
                                                   NSDate *now,
                                                   NSString *_Nullable *_Nullable backupPath,
                                                   NSError **error);

/* Copies the valid GMSE01 saves in cardDirectory into a new, empty
 * destination folder and returns their URLs, or nil with an error. */
NSArray<NSURL *> *_Nullable SunPadCopySavesForExport(NSString *cardDirectory,
                                                     NSString *destination,
                                                     NSError **error);

NS_ASSUME_NONNULL_END
