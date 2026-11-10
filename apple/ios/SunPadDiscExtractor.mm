#import "SunPadDiscExtractor.h"

#include <atomic>
#include <filesystem>
#include <string>

#include "DiscIO/DiscExtractor.h"
#include "DiscIO/Filesystem.h"
#include "DiscIO/Volume.h"

namespace fs = std::filesystem;

// DiscIO's void directory exporter logs individual write failures and carries
// on. A partial final file still exists and preserves the expected file count,
// so check every output against the verified disc's file table before activation.
static bool VerifyExtractedFiles(const DiscIO::FileInfo &directory, const fs::path &target) {
    std::error_code error;
    if (!fs::is_directory(fs::symlink_status(target, error)) || error)
        return false;
    for (const auto &entry : directory) {
        const fs::path path = target / entry.GetName();
        if (entry.IsDirectory()) {
            if (!VerifyExtractedFiles(entry, path))
                return false;
        } else if (!fs::is_regular_file(fs::symlink_status(path, error)) || error ||
                   fs::file_size(path, error) != entry.GetSize() || error) {
            return false;
        }
    }
    return true;
}

@implementation SunPadDiscExtractor

+ (void)extractImageAtPath:(NSString *)imagePath
              toDirectory:(NSString *)destination
                  progress:(void (^)(NSString *, double))progress
                completion:(void (^)(BOOL, NSString *_Nullable))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progress(@"Opening disc image", 0.0);
            });
        }

        std::unique_ptr<DiscIO::Volume> volume =
            DiscIO::CreateVolume(imagePath.fileSystemRepresentation);
        if (!volume) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"Dolphin could not open the disc image.");
            });
            return;
        }

        const DiscIO::Partition partition = volume->GetGamePartition();
        const DiscIO::FileSystem *filesystem = volume->GetFileSystem(partition);
        if (!filesystem || !filesystem->IsValid()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"Dolphin could not read the game filesystem.");
            });
            return;
        }

        std::error_code ec;
        fs::path root = destination.fileSystemRepresentation;
        fs::create_directories(root / "files", ec);
        if (ec) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"Could not create the extraction directory.");
            });
            return;
        }

        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progress(@"Extracting system data", 0.05);
            });
        }
        if (!DiscIO::ExportSystemData(*volume, partition, root.string())) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"System-data extraction failed.");
            });
            return;
        }

        const u64 total = std::max<u64>(1, filesystem->GetRoot().GetTotalChildren());
        std::atomic<u64> completed{0};
        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progress(@"Extracting game files", 0.10);
            });
        }
        DiscIO::ExportDirectory(
            *volume, partition, filesystem->GetRoot(), true, "",
            (root / "files").string(),
            [&completed, total, progress](const std::string &path) {
                ++completed;
                if (progress) {
                    double fraction = 0.10 + 0.85 * (double)completed.load() / (double)total;
                    NSString *status = @(path.c_str());
                    dispatch_async(dispatch_get_main_queue(), ^{
                        progress(status, fraction);
                    });
                }
                return false;
            });

        const bool complete = VerifyExtractedFiles(filesystem->GetRoot(), root / "files");
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(complete, complete ? nil : @"Game-data extraction was incomplete. Check available storage and try importing again. Existing game data and saves are unchanged.");
        });
    });
}

@end
