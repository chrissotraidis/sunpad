#pragma once
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <filesystem>
#include <fstream>
#include <vector>
using u64 = uint64_t;
namespace DiscIO {
struct Partition {};
enum class ExportFailure { None, Missing, Truncated, DirectoryInsteadOfFile };
inline ExportFailure exportFailure = ExportFailure::None;
struct FileInfo {
 std::string name;
 u64 size = 0;
 bool directory = false;
 std::vector<FileInfo> children;
 u64 GetTotalChildren() const {
  u64 count = children.size();
  for (const auto& child : children) count += child.GetTotalChildren();
  return count;
 }
 const std::string& GetName() const { return name; }
 u64 GetSize() const { return size; }
 bool IsDirectory() const { return directory; }
 auto begin() const { return children.begin(); }
 auto end() const { return children.end(); }
};
struct FileSystem {
 bool IsValid() const { return true; }
 FileInfo GetRoot() const {
  return {"", 0, true, {{"fixture.dat", 4, false, {}},
                       {"nested", 0, true, {{"last.dat", 8, false, {}},
                                           {"empty.dat", 0, false, {}}}}}};
 }
};
struct Volume {
 Partition GetGamePartition() const { return {}; }
 const FileSystem* GetFileSystem(Partition) const { static FileSystem fs; return &fs; }
};
inline std::unique_ptr<Volume> CreateVolume(const char*) { return std::make_unique<Volume>(); }
inline bool ExportSystemData(const Volume&, Partition, const std::string&) { return true; }
inline void ExportDirectory(const Volume&, Partition, FileInfo, bool, const char*, const std::string& destination,
                            const std::function<bool(const std::string&)>& callback) {
 namespace fs = std::filesystem;
 fs::create_directories(fs::path(destination)/"nested");
 std::ofstream(fs::path(destination)/"fixture.dat") << "okay";
 std::ofstream(fs::path(destination)/"nested/empty.dat");
 const auto last = fs::path(destination)/"nested/last.dat";
 if (exportFailure == ExportFailure::DirectoryInsteadOfFile) fs::create_directory(last);
 else if (exportFailure != ExportFailure::Missing)
  std::ofstream(last) << (exportFailure == ExportFailure::Truncated ? "part" : "complete");
 // Like the real void exporter, an individual failure does not propagate.
 for (const auto& name : {"fixture.dat", "nested", "nested/last.dat", "nested/empty.dat"})
  callback(name);
}
}
