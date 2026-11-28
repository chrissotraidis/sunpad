# Building

Last updated: 28 November 2026, for SunPad 0.4.0.

Players don't build SunPad by hand: [PadMint](https://github.com/chrissotraidis/padmint)
does it (see the [README](../README.md#get-sunpad)). This page is for
development. The legacy engine's build is in the
[legacy engine record](LEGACY-ENGINE.md#how-a-players-copy-was-built).

## Prerequisites

- An Apple silicon Mac with full Xcode and its iOS platform. Versions checked
  are in [DEPENDENCIES.md](DEPENDENCIES.md#build-tools).
- `brew install cmake ninja llvm`. The engine is compiled with Homebrew's
  LLVM, because its game code needs a pass plugin Apple's Clang can't load.
  `SUNPAD_LLVM=/path/to/llvm` names another LLVM with `clang` and
  `llvm-config`.
- Your own GMSE01 disc image, imported in the app. No build step reads it.

## Preparing a clean checkout

```sh
git clone https://github.com/chrissotraidis/sunpad.git
cd sunpad
./scripts/bootstrap-dependencies.sh   # engine sources and MoltenVK
./scripts/check-repository.sh
```

Bootstrap refuses to overwrite a dependency checkout with local changes. Use a
fresh checkout or worktree instead of resetting one.

## The engine

```sh
./scripts/build-engine.sh iphonesimulator   # build/engine-iphonesimulator/libsms_embed.dylib
./scripts/build-engine.sh iphoneos          # build/engine-iphoneos/libsms_embed.dylib
```

A clean device build takes two to four minutes on an M3 Max and makes an 11 MB
library. The script maps source and build paths to relative names and strips
debug information, so the library carries no paths from the Mac that built
it. The debug information stays in the build folder.

## A development app

The `SunPad` scheme's "Embed Engine" phase copies the engine for the SDK being
built into the app when `SUNPAD_EMBED_ENGINE=YES`. Without it the app has no
engine and asks for a PadMint copy at launch.

**Simulator:**

```sh
./scripts/build-engine.sh iphonesimulator
xcodebuild -project SunPad.xcodeproj -scheme SunPad -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -derivedDataPath build/xcode SUNPAD_EMBED_ENGINE=YES build
xcrun simctl install booted build/xcode/Build/Products/Debug-iphonesimulator/SunPad.app
```

Import the disc in the app (**••• → Game Data**), or drop it in the app's
`Documents` folder and use **Import from SunPad Folder**.

**Your own iPhone or iPad:**

```sh
./scripts/build-engine.sh iphoneos
xcodebuild -project SunPad.xcodeproj -scheme SunPad -configuration Release \
  -sdk iphoneos -derivedDataPath build/xcode \
  SUNPAD_EMBED_ENGINE=YES CODE_SIGNING_ALLOWED=NO build
./scripts/sign-dev-app.sh build/xcode/Build/Products/Release-iphoneos/SunPad.app \
  "IDENTITY" path/to/profile.mobileprovision
xcrun devicectl device install app --device DEVICE_ID \
  build/xcode/Build/Products/Release-iphoneos/SunPad.app
```

`sign-dev-app.sh` signs the app and its libraries with an Apple Development
identity and a profile covering `com.sunpad.SunPad`. Installing over an
existing SunPad keeps its data only with the same bundle identifier and team.
Back up the app's container first when it holds a save you care about.

## Scripted routes

```sh
./scripts/run-engine-route.sh DEVICE_OR_SIMULATOR_ID plaza|bianco|ricco|gelato [SECONDS]
```

The route starts a new file on file A with `SMS_AUTOPRESS` input, warps to the
area with `SMS_WARP` and prints the engine's frame-time statistics from
`Engine.log`. Other `SMS_*` variables already set, such as
`SMS_FRAME_RATE=60`, are passed on. A route on a new file writes that file to
the app's card: use `SMS_SAVE_DIR` to point the engine at a scratch card
when the device holds a real save.

## The published app and a player's copy

```sh
./scripts/build-ios-app.sh                                  # artifacts/SunPad-v0.4.0-ios-unsigned.ipa
./scripts/package-ios.sh artifacts/SunPad-v0.4.0-ios-unsigned.ipa \
  build/engine-iphoneos/libsms_embed.dylib                  # artifacts/SunPad-v0.4.0-ios-personal-unsigned.ipa
```

`build-ios-app.sh` builds the Release app without an engine and packages it.
`package-ios.sh` adds an engine to the published app, as PadMint does, and both
run `audit-ios-package.sh` on what they make. The published app must have no
engine and no game code. A player's copy must have an arm64 engine for iOS 16
that exports only `sms_embed_*` and links only libSystem, libc++ and
CoreFoundation. Neither may hold game data, saves, logs, signing material or
personal paths. Both IPAs are unsigned. A player's copy is personal and must
never be published.

## Through PadMint

PadMint reads [padmint.json](../padmint.json): it bootstraps the engine sources
(`--sources-only`), runs `build-engine.sh iphoneos`, then `package-ios.sh` on
the published IPA from the release. To check a candidate as a player would,
run PadMint's `scripts/player-check.sh sunpad ios - SUNPAD_CHECKOUT
PUBLISHED.ipa` from PadMint's `main` (see [TESTING.md](TESTING.md)).

## Deployment targets

The app and engine require iOS and iPadOS 16 on arm64. The engine's Simulator
build runs on Apple silicon Simulators only. Apple TV and Mac builds of the
engine exist as development work and aren't part of 0.4.0 (see
[TVOS.md](TVOS.md) and [MACOS.md](MACOS.md)).
