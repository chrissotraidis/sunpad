#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEPENDENCY_ROOT="${SUNPAD_TVOS_DEPENDENCY_ROOT:-$ROOT/build/tvos-deps}"
MG="$DEPENDENCY_ROOT/ModernGekko"
MG_REV=0514d9f03f8602809f66fc92fdca87d30e752997
DOLPHIN_REV=13e492094902644b0d113c586300d358640f9e19
DOLRECOMP_REV=fa0cf619e8d7eb8cba7eaf55267a12caaebb46aa

mkdir -p "$DEPENDENCY_ROOT"
if [[ ! -d "$MG/.git" ]]; then
  git clone https://github.com/ExpansionPak/ModernGekko.git "$MG"
  git -C "$MG" checkout --detach "$MG_REV"
fi
[[ "$(git -C "$MG" rev-parse HEAD)" = "$MG_REV" ]] || {
  echo "unexpected tvOS ModernGekko revision in $MG" >&2
  exit 1
}

git -C "$MG" submodule update --init vendor/dolphin
SUBMODULES=(
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
git -C "$MG/vendor/dolphin" submodule update --init "${SUBMODULES[@]}"
git -C "$MG/vendor/dolphin/Externals/cubeb/cubeb" submodule update --init --recursive
[[ "$(git -C "$MG/vendor/dolphin" rev-parse HEAD)" = "$DOLPHIN_REV" ]] || {
  echo "unexpected tvOS Dolphin revision" >&2
  exit 1
}
[[ "$(git -C "$MG/vendor/dolphin/DolRecomp" rev-parse HEAD)" = "$DOLRECOMP_REV" ]] || {
  echo "unexpected tvOS DolRecomp revision" >&2
  exit 1
}

apply_patchset() {
  local checkout=$1 marker=$2
  shift 2
  local patches=("$@")
  local fingerprint current
  fingerprint="$(shasum -a 256 "${patches[@]}" | shasum -a 256 | awk '{print $1}')"
  current="$(git -C "$checkout" diff --ignore-submodules=all | shasum -a 256 | awk '{print $1}')"
  if [[ -f "$marker" && "$(<"$marker")" = "$fingerprint $current" ]]; then
    return
  fi
  if ! git -C "$checkout" diff --ignore-submodules=all --quiet; then
    echo "unexpected local changes in $checkout; remove $DEPENDENCY_ROOT and retry" >&2
    exit 1
  fi
  local patch
  for patch in "${patches[@]}"; do
    git -C "$checkout" apply --check "$patch"
    git -C "$checkout" apply "$patch"
  done
  current="$(git -C "$checkout" diff --ignore-submodules=all | shasum -a 256 | awk '{print $1}')"
  printf '%s %s\n' "$fingerprint" "$current" >"$marker"
}
apply_patchset "$MG" "$DEPENDENCY_ROOT/.moderngekko-patchset" \
  "$ROOT/patches/ModernGekko/0001-sunpad-apple-runtime.patch" \
  "$ROOT/patches/ModernGekko/0002-sunpad-tvos-surround.patch"
apply_patchset "$MG/vendor/dolphin" "$DEPENDENCY_ROOT/.dolphin-patchset" \
  "$ROOT/patches/ModernGekko-dolphin/0001-sunpad-ios-runtime.patch" \
  "$ROOT/patches/ModernGekko-dolphin/0002-sunpad-tvos-surround.patch"
echo "Isolated tvOS dependencies are pinned and patched: $DEPENDENCY_ROOT"
