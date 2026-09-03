#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
toolchain="$repo_root/scripts/tvos-device-toolchain.cmake"
build_script="$repo_root/scripts/tvos-build-core-device.sh"
runtime_patch="$repo_root/patches/ModernGekko/0001-sunpad-apple-runtime.patch"
dolphin_patch="$repo_root/patches/ModernGekko-dolphin/0001-sunpad-ios-runtime.patch"

grep -Fq 'set(CMAKE_SYSTEM_NAME tvOS)' "$toolchain"
grep -Fq 'set(CMAKE_SYSTEM_VERSION 17.0)' "$toolchain"
grep -Fq 'set(CMAKE_SYSTEM_PROCESSOR arm64)' "$toolchain"
grep -Fq 'set(CMAKE_OSX_SYSROOT appletvos CACHE STRING "")' "$toolchain"
grep -Fq 'set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "")' "$toolchain"
grep -Fq 'set(CMAKE_OSX_DEPLOYMENT_TARGET 17.0 CACHE STRING "")' "$toolchain"
grep -Fq 'export DEVELOPER_DIR=/Applications/Xcode-27-beta-5.app/Contents/Developer' \
  "$build_script"
grep -Fq -- '-DCMAKE_SYSTEM_NAME=tvOS' "$build_script"
grep -Fq -- '-DCMAKE_SYSTEM_VERSION=17.0' "$build_script"
grep -Fq -- '-DCMAKE_OSX_SYSROOT=appletvos' "$build_script"
grep -Fq -- '-DCMAKE_OSX_ARCHITECTURES=arm64' "$build_script"
grep -Fq -- '-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0' "$build_script"
grep -Fq -- 'BUILD="$MG/build-tvos-appletvos-public"' "$build_script"
grep -Fq -- 'ninja -C "$BUILD" libmoderngekko.a -j8' "$build_script"

for forbidden in widescreen Dolby rumble ios-provision package-ios; do
  if grep -Fqi -- "$forbidden" "$build_script"; then
    echo "tvOS core build script contains forbidden M1 surface: $forbidden" >&2
    exit 1
  fi
done

python3 - "$runtime_patch" "$dolphin_patch" <<'PY'
import pathlib
import sys

for raw_path in sys.argv[1:]:
    path = pathlib.Path(raw_path)
    additions = [
        line[1:]
        for line in path.read_text().splitlines()
        if line.startswith("+") and not line.startswith("+++")
    ]
    for line in additions:
        if 'CMAKE_SYSTEM_NAME STREQUAL "iOS"' in line:
            if 'CMAKE_SYSTEM_NAME STREQUAL "tvOS"' not in line:
                raise SystemExit(f"iOS-only CMake condition remains in {path}: {line}")
        if "__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__" in line:
            if "__ENVIRONMENT_TV_OS_VERSION_MIN_REQUIRED__" not in line:
                raise SystemExit(f"iOS-only availability guard remains in {path}: {line}")

dolphin_text = pathlib.Path(sys.argv[2]).read_text()
if "#elif TARGET_OS_IOS || TARGET_OS_TV" not in dolphin_text:
    raise SystemExit("Metal shader platform branch does not include tvOS")
if (
    "#if defined(_M_ARM_64) && !defined(__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__)"
    not in dolphin_text
    or "!defined(__ENVIRONMENT_TV_OS_VERSION_MIN_REQUIRED__)" not in dolphin_text
):
    raise SystemExit("StaticRecomp fallback JIT guard does not exclude tvOS")
PY

ref_root="$repo_root/ref/ModernGekko"
if [[ -f "$ref_root/CMakeLists.txt" ]]; then
  grep -Fq \
    'if(CMAKE_SYSTEM_NAME STREQUAL "iOS" OR CMAKE_SYSTEM_NAME STREQUAL "tvOS")' \
    "$ref_root/CMakeLists.txt"
  grep -Fq '#elif TARGET_OS_IOS || TARGET_OS_TV' \
    "$ref_root/vendor/dolphin/Source/Core/VideoBackends/Metal/MTLUtil.mm"
fi

echo "tvOS core configuration checks passed"
