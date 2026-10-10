#!/usr/bin/env bash
# Prepare pinned forks without applying patches or discarding local work.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# = 0 || ( $# = 1 && "$1" = --sources-only ) ]] || {
  echo "usage: $0 [--sources-only]" >&2; exit 2;
}
python3 "$ROOT/scripts/dependency-lock.py" --declarations-only
# Preflight every existing checkout before updating any part of the graph.
python3 - "$ROOT" <<'PYCHECK'
import json, pathlib, subprocess, sys
root=pathlib.Path(sys.argv[1])
for pin in json.loads((root/'config/dependencies.lock.json').read_text())['repositories']:
    path=root/pin['path']
    if path.is_symlink():
        sys.exit(f'Preserved symlink at {path}; use a fresh checkout.')
    if (path/'.git').exists():
        dirty=subprocess.check_output(['git','-C',str(path),'status','--porcelain','--untracked-files=all','--ignore-submodules=none'],text=True)
        if dirty:
            sys.exit(f'Preserved modified dependency at {path}; use a fresh checkout.')
PYCHECK
git -C "$ROOT" submodule sync --recursive
git -C "$ROOT" submodule update --init -- ref/ModernGekko ref/ModernGekko-tvOS ref/ModernGekko-Template
for MG in "$ROOT/ref/ModernGekko" "$ROOT/ref/ModernGekko-tvOS"; do
  git -C "$MG" submodule update --init -- vendor/dolphin
  git -C "$MG/vendor/dolphin" submodule update --init -- DolRecomp
done
if [[ "${1:-}" != --sources-only ]]; then
REQUIRED_DOLPHIN_SUBMODULES=(
  DolRecomp
  Externals/SDL/SDL Externals/SFML/SFML Externals/bzip2/bzip2
  Externals/cpp-optparse/cpp-optparse Externals/cubeb/cubeb
  Externals/curl/curl Externals/enet/enet Externals/fmt/fmt
  Externals/glslang/glslang Externals/hidapi/hidapi-src
  Externals/imgui/imgui Externals/implot/implot Externals/libspng/libspng
  Externals/libusb/libusb Externals/lz4/lz4
  Externals/minizip-ng/minizip-ng Externals/pugixml/pugixml
  Externals/spirv_cross/SPIRV-Cross Externals/tinygltf/tinygltf
  Externals/watcher/watcher Externals/xxhash/xxHash
  Externals/zlib-ng/zlib-ng Externals/zstd/zstd
)
# Dolphin's Linux build also needs cpp-ipc (PadMint builds the game module on Linux).
if [[ "$(uname -s)" = Linux ]]; then
  REQUIRED_DOLPHIN_SUBMODULES+=(Externals/cpp-ipc/cpp-ipc)
fi
for MG in "$ROOT/ref/ModernGekko" "$ROOT/ref/ModernGekko-tvOS"; do
 git -C "$MG/vendor/dolphin" submodule update --init "${REQUIRED_DOLPHIN_SUBMODULES[@]}"
git -C "$MG/vendor/dolphin/Externals/cubeb/cubeb" submodule update --init --recursive

done
fi
python3 "$ROOT/scripts/dependency-lock.py"
echo "SunPad pinned fork sources are ready; no patches were applied."
