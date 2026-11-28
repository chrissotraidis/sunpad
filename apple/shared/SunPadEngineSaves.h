#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* Moves saves between SunPad's Dolphin GCI folder and the decompilation
 * engine's memory card (docs/DECOMP-ENGINE-PLAN.md, E3.5). The engine keeps
 * each card file as <name>.dat (the save's bytes), <name>.stat (the CARDStat
 * the game set, in the host's byte order) and index.txt, which lists the files
 * by slot and is written last. The GCI folder stays the format players import
 * and export; each migrated save also keeps its 64-byte GCI entry beside it
 * (<name>.direntry, which the engine ignores) so a save goes back to GCI
 * byte for byte. */

/* Writes every save on the engine's card into gciFolder as a Dolphin GCI file
 * ("01-GMSE-<name>.gci"), replacing a file of the same name. Other files in
 * the folder are left alone. */
BOOL SunPadEngineCardToGCIFolder(NSString *engineCard, NSString *gciFolder, NSError **error);

/* Replaces the engine's card with the valid GMSE01 saves in gciFolder. */
BOOL SunPadGCIFolderToEngineCard(NSString *gciFolder, NSString *engineCard, NSError **error);

/* The engine's first launch: copies the GCI folder's saves to an engine card
 * that has no index yet. The GCI folder is never changed. Returns YES when the
 * card is ready, including when there was nothing to copy. */
BOOL SunPadMigrateGCIFolderToEngineCard(NSString *gciFolder, NSString *engineCard, NSError **error);

NS_ASSUME_NONNULL_END
