#!/usr/bin/env python3
"""SunPad's PadMint steps on Windows, matching the Mac and Linux shell scripts.

  build.py dependencies [--sources-only]   scripts/bootstrap-dependencies.sh
  build.py prepare DISC                    scripts/prepare-game.sh
  build.py module TOOLCHAIN BUILD_DIR      scripts/build-ios-module.sh
  build.py tools                           the desktop tools only (CI, no disc)

prepare checks the disc's SHA-256, builds ModernGekko's desktop tools (dolrecomp and
moderngekko-port) with Visual Studio's C++ compiler, extracts the disc and translates it
to C. module compiles those sources into the iPhone game module with PadMint's
open-source iPhone SDK ({ios_toolchain}); it needs no Visual Studio.

Needs Python 3.9+, Git, CMake and Ninja (PadMint supplies them) and, for prepare and
tools, Visual Studio 2022 or newer (or its Build Tools) with "Desktop development with C++".
Job limit: SUNPAD_JOBS, else CMAKE_BUILD_PARALLEL_LEVEL, else 8.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
MG = ROOT / "ref/ModernGekko"
TPL = ROOT / "ref/ModernGekko-Template"
GAME = TPL / "extracted/Super-Mario-Sunshine"
MODULES = TPL / "build/modules-macos14"
MARKER = GAME / ".sunpad-source-sha256"
DESKTOP_BUILD = MG / "build-desktop-tools-public"
EXPECTED_SHA256 = "67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d"
GAME_FILES = 174

# Long paths for Dolphin's externals; no line-ending conversion, so every computer
# translates byte-identical sources.
GIT = ["git", "-c", "core.longpaths=true", "-c", "core.autocrlf=false"]
DOLPHIN_SUBMODULES = [
    "DolRecomp",
    "Externals/SDL/SDL", "Externals/SFML/SFML", "Externals/bzip2/bzip2",
    "Externals/cpp-optparse/cpp-optparse", "Externals/cubeb/cubeb",
    "Externals/curl/curl", "Externals/enet/enet", "Externals/fmt/fmt",
    "Externals/glslang/glslang", "Externals/hidapi/hidapi-src",
    "Externals/imgui/imgui", "Externals/implot/implot", "Externals/libspng/libspng",
    "Externals/libusb/libusb", "Externals/lz4/lz4",
    "Externals/minizip-ng/minizip-ng", "Externals/pugixml/pugixml",
    "Externals/spirv_cross/SPIRV-Cross", "Externals/tinygltf/tinygltf",
    "Externals/watcher/watcher", "Externals/xxhash/xxHash",
    "Externals/zlib-ng/zlib-ng", "Externals/zstd/zstd",
    # Dolphin's Windows build also needs these two.
    "Externals/cpp-ipc/cpp-ipc", "Externals/wil",
]
# The same configuration as scripts/prepare-game.sh.
DESKTOP_OPTIONS = [
    "-DCMAKE_BUILD_TYPE=Release", "-DHAVE_PIPE2=OFF", "-DUSE_SYSTEM_LIBS=OFF",
    "-DENABLE_VULKAN=OFF", "-DENABLE_QT=OFF", "-DENABLE_TESTS=OFF", "-DUSE_DISCORD_PRESENCE=OFF",
    "-DUSE_MGBA=OFF", "-DUSE_RETRO_ACHIEVEMENTS=OFF", "-DENABLE_AUTOUPDATE=OFF",
    "-DENABLE_ANALYTICS=OFF", "-DUSE_UPNP=OFF",
]
VS_SETUP = ("In the Visual Studio Installer, install Visual Studio 2022 or newer (the free "
            "Build Tools for Visual Studio are enough) with the \"Desktop development with C++\" "
            "workload, then run PadMint again.")


def die(message, code=1):
    print(message, file=sys.stderr, flush=True)
    raise SystemExit(code)


def run(command, env=None, cwd=None):
    command = [str(part) for part in command]
    print("+ " + subprocess.list2cmdline(command), flush=True)
    status = subprocess.call(command, env=env, cwd=cwd)
    if status != 0:
        die(f"{Path(command[0]).name} failed (exit {status})")


def jobs():
    value = os.environ.get("SUNPAD_JOBS") or os.environ.get("CMAKE_BUILD_PARALLEL_LEVEL") or "8"
    if not re.fullmatch(r"[1-9][0-9]*", value):
        die(f"Build job limit must be a positive whole number without leading zeros: {value}", 2)
    return value


def posix(path):
    return Path(path).resolve().as_posix()


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_lines(path, *args):
    return subprocess.check_output(GIT + ["-C", str(path), *args], text=True)


# --- dependencies -------------------------------------------------------------------

def lock(*args):
    run([sys.executable, ROOT / "scripts/dependency-lock.py", *args])


def ignore_windows_outputs():
    """Dolphin's Windows build writes its programs to <top source>/Binary, which is
    ModernGekko's checkout here. Mark that build-output folder ignored in this
    checkout only, so the dependency check still sees unmodified sources."""
    if not (MG / ".git").exists():
        return
    exclude = Path(git_lines(MG, "rev-parse", "--git-path", "info/exclude").strip())
    if not exclude.is_absolute():
        exclude = MG / exclude
    lines = exclude.read_text().splitlines() if exclude.is_file() else []
    if "/Binary/" not in lines:
        exclude.parent.mkdir(parents=True, exist_ok=True)
        with open(exclude, "a", newline="\n") as stream:
            stream.write("/Binary/\n")


def dependencies(sources_only=False):
    lock("--declarations-only")
    pins = json.loads((ROOT / "config/dependencies.lock.json").read_text())["repositories"]
    # Preflight every existing checkout before updating any part of the graph.
    ignore_windows_outputs()
    for pin in pins:
        path = ROOT / pin["path"]
        if path.is_symlink():
            die(f"Preserved symlink at {path}; use a fresh checkout.")
        if (path / ".git").exists() and git_lines(
                path, "status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none"):
            die(f"Preserved modified dependency at {path}; use a fresh checkout.")
    run(GIT + ["-C", ROOT, "submodule", "sync", "--recursive"])
    run(GIT + ["-C", ROOT, "submodule", "update", "--init", "--",
               "ref/ModernGekko", "ref/ModernGekko-tvOS", "ref/ModernGekko-Template"])
    for mg in (MG, ROOT / "ref/ModernGekko-tvOS"):
        run(GIT + ["-C", mg, "submodule", "update", "--init", "--", "vendor/dolphin"])
        run(GIT + ["-C", mg / "vendor/dolphin", "submodule", "update", "--init", "--", "DolRecomp"])
    ignore_windows_outputs()
    if not sources_only:
        # Windows builds only the iPhone lane's desktop tools; the Apple TV lane stays
        # at its pinned sources.
        dolphin = MG / "vendor/dolphin"
        run(GIT + ["-C", dolphin, "submodule", "update", "--init", *DOLPHIN_SUBMODULES])
        run(GIT + ["-C", dolphin / "Externals/cubeb/cubeb", "submodule", "update", "--init", "--recursive"])
    lock()
    print("SunPad pinned fork sources are ready; no patches were applied.", flush=True)


# --- Visual Studio --------------------------------------------------------------------

def visual_studio_env():
    """This computer's native Visual Studio C++ environment (vcvars), with PadMint's
    CMake, Ninja and Git kept first on PATH."""
    if platform.system() != "Windows":
        die("scripts/windows/build.py prepare runs on Windows; use scripts/prepare-game.sh elsewhere")
    arm64 = platform.machine().lower() in ("arm64", "aarch64")
    component = "Microsoft.VisualStudio.Component.VC.Tools." + ("ARM64" if arm64 else "x86.x64")
    vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / \
        "Microsoft Visual Studio/Installer/vswhere.exe"
    if not vswhere.is_file():
        die("Visual Studio's C++ compiler was not found. " + VS_SETUP)
    found = json.loads(subprocess.check_output(
        [str(vswhere), "-all", "-products", "*", "-requires", component, "-format", "json", "-utf8"],
        text=True, encoding="utf-8") or "[]")
    found = [v for v in found if v.get("installationVersion", "0").split(".")[0].isdigit()
             and int(v["installationVersion"].split(".")[0]) >= 17]
    if not found:
        die("Visual Studio 2022 or newer with the C++ workload was not found. " + VS_SETUP)
    newest = max(found, key=lambda v: [int(p) for p in re.findall(r"\d+", v["installationVersion"])])
    install = Path(newest["installationPath"])
    vcvars = install / "VC/Auxiliary/Build" / ("vcvarsarm64.bat" if arm64 else "vcvars64.bat")
    if not vcvars.is_file():
        die(f"{vcvars} is missing. " + VS_SETUP)
    keep = [shutil.which(tool) for tool in ("cmake", "ninja", "git")]
    if None in keep:
        die("CMake, Ninja and Git must be on PATH (PadMint supplies them)")
    # vcvars fails on quoted PATH entries or ones with parentheses (some installers add
    # them); keep the clean ones (as BlueWake's Windows builder does).
    path = [p.strip('"') for p in os.environ.get("PATH", "").split(os.pathsep)]
    base = dict(os.environ, PATH=os.pathsep.join(p for p in path if p and "(" not in p and ")" not in p))
    output = subprocess.run(f'cmd /d /c ""{vcvars}" >nul 2>&1 && set"', capture_output=True, text=True,
                            env=base)
    if output.returncode != 0 or "INCLUDE=" not in output.stdout:
        die(f"{vcvars} failed. Repair Visual Studio in the Visual Studio Installer, then run PadMint again.")
    env = {}
    for line in output.stdout.splitlines():
        key, sep, value = line.partition("=")
        if sep and key:
            env[key] = value
    first = list(dict.fromkeys(str(Path(tool).parent) for tool in keep))
    env["PATH"] = os.pathsep.join(first + [env.pop("Path", env.get("PATH", ""))])
    if shutil.which("cl", path=env["PATH"]) is None:
        die("Visual Studio's C++ compiler (cl.exe) is missing. " + VS_SETUP)
    version = newest.get("catalog", {}).get("productDisplayVersion", newest["installationVersion"])
    print(f"Visual Studio {version}: {install}", flush=True)
    return env


def desktop_tools(env):
    run(["cmake", "-S", MG, "-B", DESKTOP_BUILD, "-G", "Ninja", "-DCMAKE_C_COMPILER=cl",
         "-DCMAKE_CXX_COMPILER=cl", *DESKTOP_OPTIONS], env=env)
    run(["cmake", "--build", DESKTOP_BUILD, "--target", "moderngekko-port", "moderngekko-run",
         "-j", jobs()], env=env)
    ignore_windows_outputs()
    for name in ("dolrecomp.exe", "moderngekko-port.exe"):
        if not (DESKTOP_BUILD / name).is_file():
            die(f"the desktop tools build did not produce {DESKTOP_BUILD / name}")


# --- translation ------------------------------------------------------------------

def check_extraction(game):
    for name in ("sys/boot.bin", "sys/main.dol"):
        if not (game / name).is_file():
            die(f"incomplete extraction, missing {name}: {game}")
    count = sum(1 for path in (game / "files").rglob("*") if path.is_file()) if (game / "files").is_dir() else 0
    if count != GAME_FILES:
        die(f"extraction has {count} game files, expected {GAME_FILES}: {game}")


def audit_generated(gen):
    """scripts/audit-generated-gmse01.sh: reject output from DolRecomp revisions that
    emitted Gekko scalar floating-point operations as host arithmetic."""
    chunks = gen / "chunks"
    if not ((gen / "generated.c").is_file() and (gen / "generated.h").is_file() and chunks.is_dir()):
        die(f"generated GMSE01 audit failed: incomplete DolRecomp output: {gen}")
    forbidden = {
        r"ctx->fpr\[[^]]+\] = \(f64\)\(f32\)\(ctx->fpr":
            "obsolete direct scalar floating-point arithmetic is present; regenerate with the pinned DolRecomp",
        r"ppc_fp_available\(":
            "obsolete out-of-line FP availability gates are present; regenerate with the pinned DolRecomp",
    }
    required = [r"ppc_fp_available_inline\(", r"ppc_psq_load_inline\(", r"ppc_psq_store_inline\(",
                r"ppc_fdivs\(", r"ppc_ps_madd_op\("]
    patterns = {pattern: re.compile(pattern) for pattern in list(forbidden) + required}
    seen = set()
    for chunk in sorted(chunks.rglob("*.c")):
        text = chunk.read_text(encoding="utf-8", errors="replace")
        seen.update(pattern for pattern, regex in patterns.items() if pattern not in seen and regex.search(text))
    for pattern, reason in forbidden.items():
        if pattern in seen:
            die(f"generated GMSE01 audit failed: {reason}")
    for pattern in required:
        if pattern not in seen:
            die("generated GMSE01 audit failed: expected corrected helper emission is missing: " + pattern)
    print(f"generated GMSE01 audit passed: {gen}", flush=True)


def generated_dir():
    active_file = MODULES / "GMSE01/active-module.txt"
    if not active_file.is_file():
        die("prepared module sources missing; run scripts/windows/build.py prepare first")
    active = Path(active_file.read_text().strip())
    if not active.is_absolute():
        active = TPL / active
    return active.parent / "dolrecomp-output/generated"


def unix_line_endings(gen):
    """dolrecomp writes its C and text output with CRLF on Windows. Rewrite it with LF so
    every computer compiles byte-identical sources (the same 225 files as Macs and Linux)."""
    for path in sorted(gen.rglob("*")):
        if path.is_file() and path.suffix in (".c", ".h", ".txt"):
            data = path.read_bytes()
            if b"\r\n" in data:
                path.write_bytes(data.replace(b"\r\n", b"\n"))


def prepare(disc):
    jobs()
    disc = Path(disc)
    if not disc.is_file():
        die("usage: build.py prepare /path/to/GMSE01.iso", 2)
    actual = sha256(disc)
    if actual != EXPECTED_SHA256:
        die(f"unsupported disc image SHA-256: {actual}\nSunPad currently supports GMSE01 USA revision 0 only.")
    dependencies()
    env = visual_studio_env()
    desktop_tools(env)
    if GAME.exists():
        if not MARKER.is_file() or MARKER.read_text().strip() != EXPECTED_SHA256:
            die(f"existing extraction is not marked for the supported image: {GAME}\n"
                "Move that ignored directory aside, then rerun this command.")
    else:
        staging = GAME.with_name(f"{GAME.name}.importing.{os.getpid()}")
        try:
            run([DESKTOP_BUILD / "dolrecomp.exe", "extract", disc.resolve(), staging], env=env)
            check_extraction(staging)
            with open(staging / ".sunpad-source-sha256", "w", newline="\n") as stream:
                stream.write(EXPECTED_SHA256 + "\n")
            staging.rename(GAME)
        finally:
            if staging.exists():
                shutil.rmtree(staging)
    check_extraction(GAME)
    # moderngekko-port translates the game and then builds a module for this computer.
    # Only the translated sources are used here (module makes the iPhone module), so
    # build that local module quickly, without optimization.
    run([DESKTOP_BUILD / "moderngekko-port.exe", "build", GAME, "--backend", "c",
         "--toolchain", "msvc", "--opt-level", "0", "--output", MODULES], env=env)
    unix_line_endings(generated_dir())
    audit_generated(generated_dir())
    print(f"Prepared GMSE01 at {GAME}", flush=True)


# --- iPhone module ------------------------------------------------------------------

def module(toolchain, build_dir):
    count = jobs()
    gen = generated_dir()
    if not ((gen / "generated.c").is_file() and (gen / "generated.h").is_file()):
        die("prepared module sources missing; run scripts/windows/build.py prepare first")
    unix_line_endings(gen)
    audit_generated(gen)
    if not (gen / "main.dol").is_file():
        shutil.copyfile(GAME / "sys/main.dol", gen / "main.dol")
    dolphin = MG / "vendor/dolphin"
    # Each generated chunk is one very large function. With clang 22 the SLP vectorizer
    # and the register coalescer are superlinear on such functions; these two flags keep
    # each chunk to minutes (as scripts/build-ios-module.sh and BlueWake's builds do).
    # PadMint's SDK and toolchain file move with every build, and CMake keeps the first
    # toolchain an existing build folder saw: start the folder fresh when the toolchain
    # changes, and keep its objects otherwise.
    toolchain = posix(toolchain)
    cache = Path(build_dir) / "CMakeCache.txt"
    fresh = cache.is_file() and \
        f"CMAKE_TOOLCHAIN_FILE:FILEPATH={toolchain}" not in cache.read_text(errors="replace").splitlines()
    run(["cmake", *(["--fresh"] if fresh else []), "-S", dolphin / "module-template", "-B", build_dir,
         "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_TOOLCHAIN_FILE={toolchain}",
         "-DCMAKE_C_FLAGS=-fno-slp-vectorize -mllvm -large-interval-freq-threshold=10",
         "-DGAME_ID=GMSE01", f"-DGENERATED_DIR={posix(gen)}",
         f"-DGXRUNTIME_DIR={posix(dolphin / 'GXRuntime')}",
         f"-DCHASSIS_ABI_DIR={posix(dolphin / 'Source/Core/Core/PowerPC/StaticRecomp')}"])
    run(["cmake", "--build", build_dir, "-j", count])
    print(f"Built {Path(build_dir) / 'gGMSE01_recomp.dylib'}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command")
    deps = commands.add_parser("dependencies")
    deps.add_argument("--sources-only", action="store_true")
    prep = commands.add_parser("prepare")
    prep.add_argument("disc")
    mod = commands.add_parser("module")
    mod.add_argument("toolchain")
    mod.add_argument("build_dir")
    commands.add_parser("tools")
    args = parser.parse_args()
    if args.command == "dependencies":
        dependencies(args.sources_only)
    elif args.command == "prepare":
        prepare(args.disc)
    elif args.command == "module":
        module(args.toolchain, args.build_dir)
    elif args.command == "tools":
        jobs()
        dependencies()
        desktop_tools(visual_studio_env())
        print(f"Desktop tools ready in {DESKTOP_BUILD}", flush=True)
    else:
        parser.error("choose dependencies, prepare, module or tools")


if __name__ == "__main__":
    main()
