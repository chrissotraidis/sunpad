# The legacy engine

- **Written:** 2026-11-28, before the legacy engine was removed (card R1 of
  [FINALIZE-NEW-ENGINE.md](FINALIZE-NEW-ENGINE.md)).
- **Describes:** SunPad up to commit `72c101a` on `main` (0.3.3 build 21,
  never tagged). The last legacy release is [v0.3.2](https://github.com/chrissotraidis/sunpad/releases/tag/v0.3.2)
  (`429a297`).
- **Kept for:** anyone who needs to know what SunPad ran before 0.4.0, or to
  bring it back. The tag `legacy-engine-final` and the branch `legacy-engine`
  point at `72c101a`.

SunPad 0.4.0 replaced this engine with the Super Mario Sunshine decompilation
compiled natively ([DECOMP-ENGINE-PLAN.md](DECOMP-ENGINE-PLAN.md)). Everything
below is the engine SunPad used from its first preview to 0.3.3.

## Contents

- [What it was](#what-it-was)
- [Source graph](#source-graph)
- [How a player's copy was built](#how-a-players-copy-was-built)
- [How it ran on iPhone and iPad](#how-it-ran-on-iphone-and-ipad)
- [Apple TV and Mac](#apple-tv-and-mac)
- [Settings](#settings)
- [Saves and game data](#saves-and-game-data)
- [PadMint](#padmint)
- [What it measured](#what-it-measured)
- [Open reports when it was retired](#open-reports-when-it-was-retired)
- [What was removed](#what-was-removed)
- [Bringing it back](#bringing-it-back)

## What it was

The legacy engine ran the original game program, translated, on an emulated
GameCube.

1. **Translation.** DolRecomp read `sys/main.dol` from the player's own disc and
   translated the game's PowerPC code ahead of time into C: about 226 MB of
   generated source in 221 translation units, linked into a module of about
   81 MB (`gGMSE01_recomp.dylib` on iPhone and iPad).
2. **Runtime.** ModernGekko, a fork of Dolphin's core maintained for SunPad
   (RecompCore is its Dolphin tree), ran that module. It emulated the
   GameCube's memory map and address translation, the Gekko's paired-single and
   quantized load and store instructions as helpers, the GameCube OS
   scheduler, the GX graphics FIFO with a software vertex loader, the DSP for
   audio, and DiscIO for the disc. Dolphin's Metal backend drew the picture.
3. **Fallback.** Code the module did not cover ran in Dolphin's interpreter on
   iPhone, iPad and Apple TV, where a PowerPC JIT is not allowed, and in
   JitArm64 on the Mac, which returned to the module as soon as the next
   address was covered.
4. **App.** The SunPad app (`apple/ios`, `apple/shared`) owned the window,
   touch controls, controllers, menus, import and diagnostics, and drove the
   runtime through `SunPadCoreHost`.

Game-specific fixes lived in the forks: a heat-wave instruction patch for
widescreen, the GMSE01 widescreen code, a 60 FPS Gecko code, an idle hint for
the game's scheduler wait loop at `80348814`, and a resolver bypass for
DOL-only code.

## Source graph

Pinned in `config/dependencies.lock.json` at `72c101a` (copy:
[legacy/dependencies.lock.json](legacy/dependencies.lock.json),
`.gitmodules` copy: [legacy/gitmodules](legacy/gitmodules)).

| Path | Repository | Revision | Upstream |
| --- | --- | --- | --- |
| `ref/ModernGekko` | [chrissotraidis/ModernGekko](https://github.com/chrissotraidis/ModernGekko) | `e29496fb1171` | ExpansionPak/ModernGekko |
| `ref/ModernGekko/vendor/dolphin` | [chrissotraidis/RecompCore](https://github.com/chrissotraidis/RecompCore) | `724054945a90` | ExpansionPak/RecompCore |
| `ref/ModernGekko/vendor/dolphin/DolRecomp` | [chrissotraidis/DolRecomp](https://github.com/chrissotraidis/DolRecomp) | `fa0cf619e8d7` | ExpansionPak/DolRecomp |
| `ref/ModernGekko-tvOS` | chrissotraidis/ModernGekko (tvOS lane) | `3982ff05bef9` | ExpansionPak/ModernGekko |
| `ref/ModernGekko-tvOS/vendor/dolphin` | chrissotraidis/RecompCore (tvOS lane) | `6e8c569c4c57` | ExpansionPak/RecompCore |
| `ref/ModernGekko-tvOS/vendor/dolphin/DolRecomp` | chrissotraidis/DolRecomp | `fa0cf619e8d7` | ExpansionPak/DolRecomp |
| `ref/ModernGekko-Template` | [ExpansionPak/ModernGekko-Template](https://github.com/ExpansionPak/ModernGekko-Template) | `1ee85bb5e09c` | — |

The forks stay on GitHub, unarchived. Full revisions are in the lock copy.
`patches/` held historical snapshots of the iOS changes, no longer applied by
the bootstrap after 14 September 2026 ([patches/README.md](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/patches/README.md)).

## How a player's copy was built

PadMint ran these steps from SunPad's `padmint.json`
([legacy/padmint.json](legacy/padmint.json)). The disc was a build input.

| Step | Script | What it did |
| --- | --- | --- |
| Dependencies | `scripts/bootstrap-dependencies.sh` (`scripts/windows/build.py dependencies` on Windows) | Checked out the source graph above at its pins and refused modified trees |
| Prepare | `scripts/prepare-game.sh DISC` | Checked the disc's SHA-256 (`67cec163…`, GMSE01 revision 0), built DolRecomp and ModernGekko's desktop tools, extracted the disc to `ref/ModernGekko-Template/extracted/Super-Mario-Sunshine` and generated the C module sources |
| Translate (Mac) | `scripts/ios-build-core-device.sh` | Built the runtime for iOS with Xcode, the toolchain file `ios-device-toolchain.cmake` and `ios-provision-device.sh`, and compiled the module to `build/ios-module-device/gGMSE01_recomp.dylib` |
| Package (Mac) | `scripts/package-ios.sh APP MODULE OUTPUT` | Put the module in the published app (`SunPad-v{version}-ios-unsigned.ipa`) and audited it with `audit-ios-package.sh` |
| Module (Linux, Windows) | `scripts/build-ios-module.sh`, `scripts/windows/build.py module` | Compiled the module with PadMint's open-source iPhone SDK. PadMint checked its imports and added it to the published app |
| Mac app | `scripts/package-macos-app.sh` | Built `build-macos/SunPad.app` around the desktop runner and the module, then PadMint versioned, signed and zipped it |

The published app (`scripts/build-ios-app.sh`) held the runtime and no game
code. Requirements: 30 GB free, git, CMake, Ninja, Python 3 and ripgrep, full
Xcode on a Mac, Visual Studio C++ build tools on Windows. A first Windows
11 ARM64 build took 1,591 s for the tools and 8,556 s for the module.

Development builds used `scripts/ios-build-core.sh` (Simulator),
`ios-provision.sh`, `stage1-run.sh` and `stage1-status.sh` (desktop smoke
runs), `bench-route.sh` (desktop benchmarks), `fetch-gmse01-symbols.sh` and
`symbolize-profile.py` (profiles named with the CC0 symbol map),
`audit-generated-gmse01.sh` (rejected output from DolRecomp revisions with a
known scalar bug), `gcpipe.py` and `sunpad-capture.py` (scripted input and
captures), and `check-apple-build.sh` (CI link check without game inputs).

## How it ran on iPhone and iPad

- **Boot.** `SunPadGameViewController` looked for the extracted game root
  (`Library/Application Support/SunPad/GameData/GMSE01`), the retained disc
  image and the module (bundled by PadMint, or named in
  `apple/ios/Provisioned/dev-config.plist` for development), then started
  `SunPadCoreHost` on a background game thread. The status line showed
  Preparing runtime, Starting game and Waiting for first frame.
- **Runtime.** `SunPadCoreHost.mm` created `moderngekko::Runtime` with the
  view's `CAMetalLayer` as its render surface, applied settings through
  Dolphin's `Config::SetCurrent` (keys below), and pinned the CPU and video
  work to one thread. The dual-core split was rejected after it desynchronized
  the GX FIFO.
- **Input.** Touch and controller state (`SunPadInputState`, merged by
  `SunPadInputMixer`) was encoded by `SunPadInputPipeEncoder` and written to a
  pipe read by Dolphin's Pipes device as GameCube controller 1.
- **Audio.** Dolphin's DSP emulation through its iOS audio backend, paused
  with the runtime.
- **Lifecycle.** The host paused the runtime and deactivated the audio session
  on backgrounding and on audio interruptions, retried until the core reported
  Paused, and gave saves a two-second flush window.
- **Diagnostics.** `runtime.log` every ten seconds: FPS, speed ratio, EFB size,
  thermal state, Low Power Mode, CPU, memory and the busiest threads.

## Apple TV and Mac

- **Apple TV** (`SunPadTV` target, `apple/tvos/SunPadTVAppDelegate.mm`):
  tvOS 17 or later, the tvOS runtime lane, original 30 FPS, 16:9, 1x, one
  Extended Gamepad. Game data was staged from a Mac with
  `stage-tvos-game-data.sh` into `Library/Caches/SunPad`, which tvOS may purge,
  with `backup-tvos-state.sh` and `collect-tvos-diagnostics.sh` for testers.
  Built with `tvos-build-core-device.sh`, `tvos-provision-device.sh` and
  `package-tvos.sh`, audited with `audit-tvos-app.sh` and
  `audit-tvos-package.sh`. See [TVOS.md](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/TVOS.md).
- **Mac** (`apple/macos`): `SunPad.app` ran ModernGekko's desktop frontend
  (`SunPadFrontend`) with `default-config.ini` (Metal, 1920x1080 internal) and
  `default-GCPadNew.ini` (keyboard layout), data in
  `~/Library/Application Support/SunPad`. See [MACOS.md](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/MACOS.md).

## Settings

Stored in `NSUserDefaults` (`apple/shared/SunPadSettings.mm`). The new engine
keeps the same keys, so 0.4.0 reads them on upgrade.

| Key | Legacy meaning | Dolphin setting |
| --- | --- | --- |
| `SunPadRenderScale` | Render Resolution 1x-4x | `GFX_EFB_SCALE`, capped by `GFX_MAX_EFB_SCALE` |
| `SunPadAspectRatioMode` | 0 Original 4:3, 1 16:9, 2 Fill Screen | `GFX_ASPECT_RATIO` (`ForceStandard`, `ForceWide`, `CustomStretch` with `GFX_CUSTOM_ASPECT_RATIO_WIDTH/HEIGHT`), `GFX_WIDESCREEN_HACK` off, GMSE01 widescreen code and heat-wave suppression on in wide modes |
| `SunPadExperimental60FPS` | 60 FPS Patch (a Gecko code) | runtime config `enable_gmse01_60fps` |
| `SunPadExperimentalPerformanceMode` | Reduced CPU Clock 90% | emulated clock 90%, single core, `userInitiated` QoS |
| `SunPadExperimentSafetyResetVersion` | one-time reset of both experiments | — |
| `SunPadShowFPSCounter`, `SunPadControllerRumble`, `SunPadInvertCStickVertical`, `SunPadModernCStickHorizontal`, `SunPadHideControlsOnController`, `SunPadControlOpacity`, `SunPadControlOrigins`, `SunPadControlSizeScale(s)`, `SunPadExperimentalDPadOrigin` | shell settings | — |
| `SunPadRetainedGameDataPath`, `SunPadExtractedGameRoot` | the retained image and the extracted root | — |

The static-recomp idle hint was `MAIN_STATICRECOMP_IDLE_PC`.

## Saves and game data

- **Saves:** Dolphin GCI files in `Library/Application Support/SunPad/GC/USA/Card A`
  (one `01-GMSE-super_mario_sunshine.gci` and a `.bak`). The new engine copies
  them into its own card (`Engine/card-a`) on first launch and never changes
  this folder, so a downgrade finds the saves as the legacy engine left them,
  without progress made on the new engine. Export Saves turns the new engine's
  progress back into GCI files.
- **Game data:** the retained image in `GameData/` and the 174-file extracted
  tree in `GameData/GMSE01`, made by `SunPadDiscExtractor` (Dolphin's DiscIO)
  during import with staged, atomic activation and rollback.
- **Config:** Dolphin's `Config/*.ini` (`GCPadNew.ini`, `GFX.ini`,
  `Dolphin.ini`).

## PadMint

- Recipe: [legacy/padmint.json](legacy/padmint.json), kind
  `disc-translation`, disc as a build input, iPhone hosts Mac, Windows (ARM64,
  x64) and Linux (ARM64, x86-64), Mac target on Apple silicon.
- Catalog entry as it stood at PadMint `087a083`:
  [legacy/padmint-catalog-sunpad.json](legacy/padmint-catalog-sunpad.json).
- Compatibility: "Build here (experimental)" on Windows and Linux since 0.3.0.
  A Windows 11 ARM64 copy was installed and played on an iPad Pro, including a
  save and a reload after a cold relaunch.

## What it measured

| Measurement | Result | Source |
| --- | --- | --- |
| iPhone 14, native 1x, 30 FPS, nominal thermal state | 25.7–27.1 FPS, 0.872–0.910 speed | [TESTING.md](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/TESTING.md), 13 August 2026 |
| iPhone 14, serious thermal state | 23.0–25.9 FPS, 0.785–0.875 speed | same |
| iPhone 14, worst interval | 0.759 speed, game thread near 100% of one core | [APPLE-PERFORMANCE-RESEARCH.md](APPLE-PERFORMANCE-RESEARCH.md) |
| What full speed would have needed | about 24% less work on the critical path | same |
| iPhone 15 Pro (player report) | 29.9–30.0 FPS in five of six samples, about 484 MiB resident | [TESTING.md](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/TESTING.md), report `SP-133DE3C9` |
| iPad Pro 12.9-inch (M2) | 30 FPS in the supported mode | [STATUS.md](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/STATUS.md) |
| 60 FPS Patch, iPad | 59.7–60.0 FPS in telemetry, judged unusable in hands-on play | [TESTING.md](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/TESTING.md) |
| Reduced CPU Clock 90% | CPU headroom in traces, then visual corruption at 4x and unusably slow on iPad | [STATUS.md](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/STATUS.md) |
| Dual-core CPU and video threads | Rejected: GX FIFO desynchronization | [TESTING.md](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/TESTING.md) |
| QoS changes alone | 22.0–27.7 FPS, no gain | [TESTING.md](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/TESTING.md) |

For comparison, the new engine played Delfino Plaza and Bianco Hills on the
iPhone 14 at 30.0 FPS (33.4 ms per frame) on 23 November 2026
([IMPROVEMENT-LOG.md](IMPROVEMENT-LOG.md)).

## Open reports when it was retired

- [#12](https://github.com/chrissotraidis/sunpad/issues/12) Slow downs, the
  single-core ceiling above.
- [#23](https://github.com/chrissotraidis/sunpad/issues/23) Wide screen issues.
- [#54](https://github.com/chrissotraidis/sunpad/issues/54) The app won't launch.

## What was removed

Removed from `main` for 0.4.0, in the commits listed under
[Reverting the removal](#reverting-the-removal).

- **Gitlinks and lock entries:** `ref/ModernGekko`, `ref/ModernGekko-tvOS`,
  `ref/ModernGekko-Template` and their nested repositories.
- **Patches:** `patches/` (`ModernGekko/`, `ModernGekko-dolphin/`,
  `README.md`), and `config/dependency-migration.json`, which mapped their
  hashes to fork commits.
- **App:** `apple/ios/SunPadCoreHost.mm`, `apple/ios/SunPadDiscExtractor.{h,mm}`,
  `apple/shared/SunPadInputPipeEncoder.{h,mm}`, `apple/tvos/` and the
  `SunPadTV` target, `apple/macos/SunPad`, `default-config.ini`,
  `default-GCPadNew.ini`, and the legacy branches of
  `SunPadGameViewController.mm`, `SunPadGameOverlay.mm` and
  `SunPadAppDelegate.mm`. `SunPadCoreHost.h` stays: the new host implements
  the same interface.
- **Scripts:** `prepare-game.sh`, `build-ios-module.sh`, `build-ios-app.sh`,
  `ios-build-core.sh`, `ios-build-core-device.sh`, `ios-provision.sh`,
  `ios-provision-device.sh`, `ios-device-toolchain.cmake`,
  `ios-simulator-toolchain.cmake`, `tvos-build-core-device.sh`,
  `tvos-build-core-simulator.sh`, `tvos-provision-device.sh`,
  `tvos-device-toolchain.cmake`, `prepare-tvos-dependencies.sh`,
  `stage-tvos-game-data.sh`, `package-tvos.sh`, `audit-tvos-app.sh`,
  `audit-tvos-package.sh`, `backup-tvos-state.sh`,
  `collect-tvos-diagnostics.sh`, `package-macos-app.sh`,
  `fetch-gmse01-symbols.sh`, `symbolize-profile.py`,
  `audit-generated-gmse01.sh`, `stage1-run.sh`, `stage1-status.sh`,
  `gcpipe.py`, `sunpad-capture.py`, `bench-route.sh`, `check-apple-build.sh`,
  `deploy-ios-device.sh`, `scripts/windows/`.
- **Tests** for the removed code, and the CI jobs that built the runtime and
  ran the Windows route.

The exact list is whatever the removal commits deleted. `git show --stat` on
each of them is the authority.

## Bringing it back

### Rebuilding the last legacy release

1. Check out `v0.3.2` (the last release) or `legacy-engine-final` (0.3.3,
   unreleased) in a fresh clone.
2. Run `./scripts/bootstrap-dependencies.sh`. It fetches the forks above at
   their pins, which stay on GitHub.
3. Run `./scripts/prepare-game.sh /path/to/GMSE01.iso` and follow
   [BUILDING.md](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/BUILDING.md)
   at that tag.
4. For players, publish a release from the `legacy-engine` branch with a
   version above the current one, and restore PadMint's catalog entry from
   [legacy/padmint-catalog-sunpad.json](legacy/padmint-catalog-sunpad.json).
   PadMint reads the recipe from the release itself.

A device that installs it over 0.4.0 keeps the Dolphin card as 0.3.x left it.
Progress made on the new engine has to come back through Export Saves on 0.4.0
and Import Dolphin Save on the legacy build.

### Reverting the removal

Revert the removal commits on `main` newest first, then the commit that made
the engine the SunPad app, then run `bootstrap-dependencies.sh` to restore the
gitlinks from the restored lock. Restore PadMint's catalog entry as above.

| Order | Commit | What it reverts |
| --- | --- | --- |
| 1 | `2576d0d` | PadMint recipe for the new engine (or restore [legacy/padmint.json](legacy/padmint.json)) |
| 2 | `25260e3` | The engine-layout package audit |
| 3 | `d7251ea` | CI for the published app and the engine |
| 4 | `dd0c46f` | `package-ios.sh` and `build-ios-app.sh` for the engine app |
| 5 | `9ead6ca` | Gitlinks, lock entries and `patches/` |
| 6 | `d40ec83` | Legacy build scripts and tests |
| 7 | `f2cc059` | Legacy app code (host, extractor, input pipe, legacy menu) |
| 8 | `44a305e` | The Apple TV app |
| 9 | `ef1856c` | The engine app taking the SunPad target and identity |

Later commits on `main` touch the same files (documentation in particular),
so expect conflicts to resolve by hand. Reverting all nine leaves the engine
fork pinned beside the legacy engine, as it was in the 0.3.x line's last
development builds.
