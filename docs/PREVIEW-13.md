# Preview 13: maintained-fork release

> [!NOTE]
> **History (28 November 2026).** This document describes the legacy engine,
> the game's PowerPC code translated ahead of time on a Dolphin-derived runtime,
> which SunPad used through 0.3.x. SunPad 0.4.0 replaced it with the
> decompilation engine. See the [legacy engine record](LEGACY-ENGINE.md) and,
> for the current app, [ARCHITECTURE.md](ARCHITECTURE.md).

Preview 13 supplies unsigned iPhone/iPad and experimental Apple TV IPAs, both
version 0.1.0 build 13. It rebuilds the runtime and GMSE01 module from the
[maintained dependency graph](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/DEPENDENCIES.md), with the Apple and tvOS audio
implementations kept separate. It includes the revised credits, original
third-party license texts and recursive source references. It introduces no new
gameplay feature or performance claim.

## Downloads and evidence

Use the Preview 13 release (retired):

- `SunPad-0.1.0-preview.13-unsigned.ipa`: iPhone/iPad, arm64, iOS target 16.0.
- `SunPad-0.1.0-preview.13-tvos-unsigned.ipa`: Apple TV, arm64, tvOS target 17.0.
- `SHA256SUMS.txt`: hashes of the downloadable artifacts.
- `build-provenance.json`: app/dependency commits, SDK/compiler versions, generation
  inputs and hashes, build flags, runtime archive and module hashes.
- `SunPad-0.1.0-preview.13-source.tar.gz`: corresponding redistributable app,
  runtime, compiler and initialized dependency sources, including original notices.

The source archive excludes game images, extracted assets, generated game code,
saves and signing material. Reproduce the module privately with the supported
GMSE01 USA revision-0 image; its required hash is enforced by `prepare-game.sh`.
Each IPA contains the required AOT executable module, but no game image or assets.

## Reproduction

Check out the app commit recorded in `build-provenance.json`, initialize the
pinned dependencies, and use the recorded Xcode/toolchain:

```sh
./scripts/bootstrap-dependencies.sh
./scripts/prepare-game.sh /path/to/GMSE01.iso
SUNPAD_IOS_MODULE_BUILD=/tmp/sunpad-preview13-module-ios ./scripts/ios-build-core-device.sh
SUNPAD_TVOS_MODULE_BUILD=/tmp/sunpad-preview13-module-tvos ./scripts/tvos-build-core-device.sh
xcodebuild -project SunPad.xcodeproj -scheme SunPad -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/SunPadPreview13IOS CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SunPad.xcodeproj -scheme SunPadTV -configuration Release \
  -sdk appletvos -destination 'generic/platform=tvOS' \
  -derivedDataPath /tmp/SunPadPreview13TV CODE_SIGNING_ALLOWED=NO build
./scripts/package-ios.sh /tmp/SunPadPreview13IOS/Build/Products/Release-iphoneos/SunPad.app \
  /tmp/sunpad-preview13-module-ios/gGMSE01_recomp.dylib /tmp/SunPad-preview13-ios.ipa
./scripts/package-tvos.sh /tmp/SunPadPreview13TV/Build/Products/Release-appletvos/SunPadTV.app \
  /tmp/SunPad-preview13-tvos.ipa
```

Use new output paths: the packagers refuse to overwrite existing outputs. The
release checks include source tests, clean runtime/app compilation, generated-code
validation, package audits and repeated packaging of identical inputs. Matching
packages do not establish byte-for-byte reproducibility across compiler versions.

## Installation and validation limits

Sign both the app and nested module with your own identity. Follow the
[iOS installation guide](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/INSTALL_IPA.md) or [Apple TV guide](INSTALL_TVOS.md).
Back up saves first and preserve the existing signing identity and bundle ID for
an in-place update. Do not uninstall to resolve a signing mismatch.

These are experimental builds. Build and archive checks do not establish a
recipient-signed installation or physical gameplay, sound, controller, performance
or save-readback acceptance. Earlier device results belong to their earlier
artifacts; Preview 13 needs its own in-place update and gameplay checks. Apple TV
state remains in purgeable cache storage, and physical Apple TV acceptance remains
open. Minimum OS settings are build targets, not verified oldest-device support.
