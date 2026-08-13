# SunPad

<p align="center">
  <strong>Super Mario Sunshine on iPhone, iPad, and Apple Silicon Mac through static recompilation and Metal.</strong><br>
  Touch controls on mobile, keyboard/controller input on Mac, and local user-supplied game-data setup.
</p>

<p align="center">
  <img src="apple/ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="180" alt="SunPad cartoon sun app icon">
</p>

<p align="center">
  <img alt="iOS and iPadOS artifact target 16+" src="https://img.shields.io/badge/iOS%20%2F%20iPadOS%20artifact%20target-16%2B-0A84FF?logo=apple">
  <img alt="Configured macOS 14+ target" src="https://img.shields.io/badge/configured%20macOS%20target-14%2B-0A84FF?logo=apple">
  <img alt="Metal renderer" src="https://img.shields.io/badge/renderer-Metal-5E5CE6">
  <img alt="Ahead-of-time static recompilation" src="https://img.shields.io/badge/PowerPC-static%20recompilation-FF9F0A">
  <img alt="Physical iPad tested" src="https://img.shields.io/badge/physical%20iPad-tested-30D158">
  <img alt="Game data not included" src="https://img.shields.io/badge/game%20data-not%20included-FF453A">
</p>

![SunPad running Super Mario Sunshine in Delfino Plaza on iPad](docs/readme/sunpad-delfino-plaza.jpg)

SunPad packages a native Apple ARM64 app around a
[DolRecomp](https://github.com/encounter/dolrecomp)-generated Super Mario
Sunshine module and the ModernGekko/Dolphin-derived compatibility runtime.
Covered PowerPC game-code regions run as ahead-of-time recompiled host code.
iPhone and iPad use interpreter fallback with no runtime PowerPC JIT; Apple
Silicon Mac uses JitArm64 only for code outside the recompiled module.
Dolphin's Metal backend renders into the Apple apps.

The mobile app imports a user-provided supported GameCube image through Files,
extracts it on-device, and provides a landscape touch controller alongside
iOS GameController support. The local macOS app provides a Metal launcher,
internal-resolution and fullscreen options, keyboard controls, and controller
selection. This repository contains the Apple integration,
patches, and reproducible tooling. It does **not** contain Super Mario
Sunshine, a GameCube image, extracted Nintendo assets, saves, or a generated
game module.

## Current status

| Area | Current result |
|---|---|
| Native app | Universal arm64 iPhone/iPad target plus a local Apple Silicon `SunPad.app` packager |
| Rendering | Dolphin Metal backend reaches the title sequence and playable Delfino Plaza gameplay |
| Game setup | Exact GMSE01 USA Rev 0 validation, staged private import, atomic activation, and real removal |
| Touch | Move stick, C-stick, grouped D-pad editing, A/B/X/Y/Z, L, analog R, Start, and a persistent settings menu |
| Controllers | Touch and iOS GameController on mobile; keyboard or connected controller on macOS; narrow A/B/X/Y/Z physical-button remapping is implemented in source and awaiting device acceptance |
| Settings | Live 1×–4× render scale, original 4:3 plus experimental widescreen/fill modes, and touch-layout settings |
| Audio | Guest-timebase defect fixed; continuous desktop and Simulator audio verified; fresh physical-device audio acceptance remains |
| Distribution | Audited unsigned Preview 2 IPA for re-signing; no game image, saves, signing material, TestFlight, or App Store release |

The mobile development build has been signed, installed, and played on a
12.9-inch iPad Pro (6th generation). Physical-device boot, Metal rendering,
Files import, on-device extraction, touch input, gameplay, and in-place app
updates have been exercised. A signed development build has also launched on
an iPhone 14, where performance is currently below the iPad experience even at
1×. For iPhone development testing, an **iPhone 15 Pro or newer is strongly
recommended**. The local arm64 macOS app bundle has been built, signed ad hoc, and
launched with its Metal and keyboard defaults. See
[the testing ledger](docs/TESTING.md) for the dated evidence and remaining
hands-on acceptance checks.

The signed iOS app and generated module now record iOS 16.0 in their final
artifact metadata. Runtime acceptance on iOS 16 hardware is still required
before treating that as verified compatibility. macOS 14.0 remains configured
but still needs final-artifact inspection and oldest-target runtime acceptance.

## Download the iPhone/iPad preview

The current public download is the unsigned
[`SunPad-0.1.0-preview.2-unsigned.ipa`](https://github.com/chrissotraidis/sunpad/releases/download/v0.1.0-preview.2/SunPad-0.1.0-preview.2-unsigned.ipa).
Preview 2 includes the promoted analog-R/grouped-D-pad baseline, accepted iPad
default mapping, controller remapping, loading and diagnostics improvements,
and the corrected ISO/GCM import flow with a Files-visible SunPad folder.
It must be re-signed with your Apple identity, including its nested
`gGMSE01_recomp.dylib`, before installation. It contains no game image or
save. Follow [`docs/INSTALL_IPA.md`](docs/INSTALL_IPA.md) for the short install
path, checksum verification, current compatibility boundary, and first launch.

## Build from source

You need:

- an Apple Silicon Mac with Xcode 26.x and its command-line tools;
- CMake, Ninja, ripgrep, Git, and Python 3;
- an Apple ID configured in Xcode for physical-device signing; and
- your own legally obtained Super Mario Sunshine USA revision 0 image
  (`GMSE01`).

From a clean clone, reproduce the reviewed dependency tree and prepare the one
supported game revision:

```sh
./scripts/bootstrap-dependencies.sh
./scripts/prepare-game.sh /path/to/GMSE01.iso
```

`bootstrap-dependencies.sh` clones the pinned public toolchain revisions and
applies the two complete SunPad patch snapshots. It never downloads game data.
`prepare-game.sh` verifies the exact supported SHA-256, builds the desktop
tools, extracts the image locally, and generates the host module inputs used
by the Apple builds. All outputs stay under ignored local paths. See
[`docs/BUILDING.md`](docs/BUILDING.md) for the full workflow.

Build the iOS Simulator core and app:

```sh
./scripts/ios-build-core.sh
xcodebuild -project SunPad.xcodeproj -scheme SunPad -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/sunpad-ddp build
```

Build for a physical iPhone or iPad:

```sh
./scripts/ios-build-core-device.sh
xcodebuild -project SunPad.xcodeproj -scheme SunPad -configuration Debug \
  -destination 'platform=iOS,id=<device-udid>' \
  -derivedDataPath /tmp/SunPadDerivedData \
  DEVELOPMENT_TEAM=<team-id> CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build
```

Build the local Apple Silicon macOS app after producing the desktop GMSE01
module from [`docs/BUILDING.md`](docs/BUILDING.md):

```sh
./scripts/package-macos-app.sh
open build-macos/SunPad.app
```

The local package may contain your locally generated game module. The package
is ignored, is not a release artifact, and must not be committed or
distributed.

Generated source trees, build products, GameCube data, saves, signing
material, and locally recompiled modules are ignored and must never be
committed.

## First launch on iPhone or iPad

SunPad never downloads or bundles game data.

1. Launch SunPad and open the **•••** menu.
2. Choose **Game Data & Saves → Change or Reimport**.
3. Select your supported raw ISO/GCM image in Files.
4. Leave SunPad open while it validates and extracts the image locally.
5. Start playing when the game finishes booting.

SunPad validates the exact raw image size, GameCube magic, `GMSE01` game code,
disc number 0, and revision 0. It copies and extracts into a unique staging
directory, checks the required extracted structure, then atomically activates
the completed import. A failed reimport leaves the prior working data in
place. **Remove Stored Game Data** deletes both the retained image and
extracted game tree after confirmation; saves are kept separately.

## First launch on Mac

Open the locally built `SunPad.app`, choose your legally obtained supported
disc image, then use **Extract and Play**. The launcher uses Metal and offers
internal-resolution and fullscreen options. It starts with keyboard controls:
WASD to move, arrow keys for the camera, J/K/U/I/O for A/B/X/Y/Z, Q/E for L/R,
and Return for Start. Connect a controller and choose it in the launcher to
replace the keyboard profile. Mac game data, configuration, and saves stay in
`~/Library/Application Support/SunPad`.

## Touch controls

SunPad uses a landscape layout designed separately for compact iPhones and
larger iPads:

- **Left:** movement stick, D-pad, and L within thumb reach.
- **Right:** camera stick, A/B/X/Y diamond, Z, R, and Start.
- **Menu:** the persistent **•••** button opens render resolution, aspect
  ratio, control, game-data, save, and diagnostic-log actions. Original 4:3
  is the default; 16:9 and Fill Screen are marked experimental.
- **Customize:** Move mode lets controls be dragged and saves normalized
  positions per device class; Reset restores the default layout.
- **Controller handoff:** a connected physical controller can hide the touch
  overlay automatically.

The four D-pad directions always move, resize, and reset as one layout group;
their gameplay hit regions remain four independent directions. R is a longer
horizontal pressure slider: touch its left edge for minimum spray pressure,
slide right for more pressure, and enter the final quarter for a haptic full
press. Keep the same finger down while sliding; moving past either edge clamps
to minimum or maximum pressure, and lifting releases R. The large-iPad default
layout is the normalized physical-iPad arrangement accepted on August 11,
2026. Phone layouts remain independently movable and are unchanged.

The **Controller Button Mapping…** menu is likewise narrow: GameCube A/B/X/Y/Z
can be assigned one-to-one across the four face buttons and right shoulder,
with conflicts swapped and a default reset. Sticks, D-pad, Start, left
shoulder, and analog triggers stay fixed so DualSense trigger pressure is not
disturbed. Focused source mapping tests pass; physical-controller acceptance
remains open.

Touch and GameController input merge through the same thread-safe GameCube
state. Button presses are edge-latched, the strongest stick input wins, and
analog triggers preserve FLUDD pressure control.

## Share a diagnostic log

If SunPad crashes or fails to start, reopen it and choose **••• → Share
Diagnostic Log…**. SunPad first asks for confirmation and describes the
metadata that can appear: OS and app versions, display and controller details,
the game-image filename, runtime errors, and diagnostic paths. App-container
and temporary-directory prefixes are redacted in newly written messages. The
snapshot does not include the game image, extracted game data, or save files.
Review the destination in the standard share sheet. For a public report, open
the [bug-report form](https://github.com/chrissotraidis/sunpad/issues/new?template=bug_report.yml)
with reproduction steps and only the smallest privacy-reviewed excerpt. Share
the complete `.log` privately only when the maintainer requests it; never
upload game data, saves, signing material, or a device container.

If SunPad cannot reopen, use **Settings → Privacy & Security → Analytics &
Improvements → Analytics Data**, select the newest entry beginning with
`SunPad`, and share that system crash report instead.

## Screenshots

<table>
  <tr>
    <td width="50%">
      <img src="docs/readme/sunpad-plaza-conversation.jpg" alt="SunPad gameplay and touch controls during a Delfino Plaza conversation">
    </td>
    <td width="50%">
      <img src="docs/readme/sunpad-isle-delfino-map.jpg" alt="SunPad showing the Isle Delfino map with touch controls">
    </td>
  </tr>
  <tr>
    <td align="center"><strong>Playable on iPad</strong><br>Native Metal gameplay with the full touch layout.</td>
    <td align="center"><strong>Menus remain usable</strong><br>Every GameCube control stays available without a separate controller.</td>
  </tr>
</table>

All screenshots come from the current physical iPad development build using
game data supplied locally by the device owner. No game data or save is part
of this repository.

## Supported game data

| Game ID | Region | Revision | Status |
|---|---|---|---|
| `GMSE01` | USA | 0 | Initial supported target |

Raw ISO/GCM images are recognized. Compressed image formats and automatic
module matching remain hardening work. The development target SHA-256 is
recorded in [the legal and provenance boundary](docs/LEGAL_AND_PROVENANCE.md)
for identification; the image itself is never tracked or distributed.

## How the local pipeline works

```text
Your GMSE01 image on the Mac
        ↓
DolRecomp-generated ARM64 module + ModernGekko/Dolphin runtime
        ↓
Signed SunPad development app
        +
Your GMSE01 image selected through Files after installation
        ↓
Private on-device extraction → Metal rendering → local gameplay and saves
```

The compile path and first-launch import are deliberately separate. Building
the app never adds the retail disc image, extracted game files, or a user save
to the bundle.

## Frequently asked questions

### Does this repository include Super Mario Sunshine?

No. You must supply your own legally obtained supported GameCube image. Do
not open issues requesting game data or download links.

### Is SunPad a GameCube emulator?

No. SunPad is a game-specific static-recompilation integration. It combines a
locally generated `GMSE01` module with a Dolphin-derived compatibility runtime;
it is not a general-purpose loader for other GameCube games.

### Does it use a JIT on iPhone or iPad?

No runtime PowerPC JIT is used. The supported game's PowerPC code is
ahead-of-time recompiled for ARM64, with the runtime interpreter handling
unrecompiled regions.

### Does it use a JIT on Apple Silicon Mac?

Only as a fallback. The ahead-of-time module executes covered game code, and
JitArm64 handles code outside that module before yielding back to it. This
ARM64 handoff includes the fix from
[ExpansionPak/RecompCore PR #6](https://github.com/ExpansionPak/RecompCore/pull/6).

### Can I download an IPA?

Yes. Download the unsigned **SunPad 0.1.0 Preview 2** IPA from
[GitHub Releases](https://github.com/chrissotraidis/sunpad/releases), then
re-sign it with your own Apple identity. It includes the required GMSE01
ahead-of-time recompiled executable module, but no disc image, extracted game
assets, save, settings, certificate, or provisioning profile. See
[`docs/INSTALL_IPA.md`](docs/INSTALL_IPA.md).

### Does the IPA work in LiveContainer?

LiveContainer is not currently a supported or verified install path. Multiple
users have reported that SunPad fails there, but no actionable LiveContainer
error or crash report has been received yet, so the cause is unknown. A current
upstream source and package review found no obvious layout defect. If you
reproduce the issue, please [submit a bug
report](https://github.com/chrissotraidis/sunpad/issues/new?template=bug_report.yml)
with LiveContainer's copied launch error or exported crash report and follow
the evidence checklist in [`docs/INSTALL_IPA.md`](docs/INSTALL_IPA.md). The
supported preview path remains re-signing both the app and its nested module,
then installing the IPA normally.

### Do saves survive an app update?

An in-place development install preserves the app container. Clean uninstall,
bundle-identifier changes, and some signing changes can remove or disconnect
local data, so back up the device container before changing those boundaries.
No save belongs in Git or a release artifact.

### Is everything finished?

No. The current build is playable and useful for development testing, but
physical-device audio re-acceptance, iPhone performance, broader scene
coverage, physical lifecycle/save acceptance, compressed image support, and
broader macOS gameplay acceptance remain explicit work. A default-off
**Experimental 60 FPS (Restart Required)** three-dot-menu option is test-only
and is known from hands-on physical-iPad testing to be unsuitable for normal
play. Original 30 FPS remains the supported default. Wii U GameCube Adapter, HD
textures, Vision Pro, Apple TV, and Eclipse/general mod support remain backlog
research rather than promised features.

## Project map

| Path | Purpose |
|---|---|
| [`scripts/bootstrap-dependencies.sh`](scripts/bootstrap-dependencies.sh) | Clone reviewed upstream revisions and apply the complete patch snapshots |
| [`scripts/prepare-game.sh`](scripts/prepare-game.sh) | Validate the supported local image and generate ignored game/module inputs |
| [`scripts/ios-build-core.sh`](scripts/ios-build-core.sh) | Build and provision the Simulator core/module |
| [`scripts/ios-build-core-device.sh`](scripts/ios-build-core-device.sh) | Build and provision the physical-device core/module |
| [`scripts/package-ios.sh`](scripts/package-ios.sh) | Create the audited unsigned developer-preview IPA |
| [`scripts/audit-ios-package.sh`](scripts/audit-ios-package.sh) | Reject game data, saves, signing material, and malformed IPA contents |
| [`scripts/package-macos-app.sh`](scripts/package-macos-app.sh) | Build the local Apple Silicon `SunPad.app` bundle |
| [`apple/ios/`](apple/ios/) | UIKit app shell, Files import, touch UI, and Apple adapter |
| [`apple/macos/`](apple/macos/) | macOS bundle metadata, launcher wrapper, and keyboard defaults |
| [`patches/ModernGekko/`](patches/ModernGekko/) | Complete ModernGekko Apple-runtime snapshot |
| [`patches/ModernGekko-dolphin/`](patches/ModernGekko-dolphin/) | Complete vendored Dolphin iOS/runtime snapshot |
| [`docs/BUILDING.md`](docs/BUILDING.md) | Exact desktop, Simulator, and device build commands |
| [`docs/ANDROID-FEASIBILITY.md`](docs/ANDROID-FEASIBILITY.md) | Source-backed Android architecture, build plan, effort, and acceptance gates |
| [`docs/TESTING.md`](docs/TESTING.md) | Dated evidence and remaining acceptance gates |
| [`docs/KNOWN_ISSUES.md`](docs/KNOWN_ISSUES.md) | Current limitations and workarounds |
| [`docs/LEGAL_AND_PROVENANCE.md`](docs/LEGAL_AND_PROVENANCE.md) | Asset, game-data, attribution, and license boundary |
| `ref/` | Ignored local game data and pinned/generated source worktrees |

## Research and credits

The recompilation path follows the public ExpansionPak ecosystem: DolRecomp,
ModernGekko, ModernGekko-Template, RecompCore, and their contributors. Dolphin
provides the compatibility-runtime foundation and Metal backend. The
[doldecomp/sms](https://github.com/doldecomp/sms) project is used as a research
reference. See [`docs/RESEARCH.md`](docs/RESEARCH.md) and
[`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md) for pins and attribution.

## Legal

SunPad is an unofficial community project and is not affiliated with or
endorsed by Nintendo. Super Mario Sunshine, Nintendo, and GameCube names and
screenshots are used only to identify compatibility and demonstrate the
project. No disc image, extracted Nintendo asset, or user save is included in
the repository or a release. The developer-preview IPA includes the required
ahead-of-time recompiled executable module. Each upstream
component retains its own license and copyright. SunPad is licensed under
GPL-3.0-or-later; see [`LICENSE`](LICENSE),
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), and
[`docs/LEGAL_AND_PROVENANCE.md`](docs/LEGAL_AND_PROVENANCE.md).

## Contributing

SunPad is an experimental source project. The most useful contributions are
reproducible device reports against the checklist in
[`docs/TESTING.md`](docs/TESTING.md). Never attach game data, extracted assets,
generated modules, or saves to an issue or pull request.
