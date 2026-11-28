# Install the experimental SunPad Apple TV build

> [!NOTE]
> **History (28 November 2026).** This document describes the legacy engine,
> the game's PowerPC code translated ahead of time on a Dolphin-derived runtime,
> which SunPad used through 0.3.x. SunPad 0.4.0 replaced it with the
> decompilation engine. See the [legacy engine record](LEGACY-ENGINE.md) and,
> for the current app, [ARCHITECTURE.md](ARCHITECTURE.md).

There is no current public tvOS IPA download or PadMint tvOS recipe. For private
source development, use the build and packaging route in `TVOS.md`, then the
staging instructions below. It is experimental Apple TV functionality, not
accepted support.

SunPad 0.1.0 Preview 13's unsigned ARM64 tvOS IPA was a hardware bring-up
artifact. Its download is retired. The historical filename
`SunPad-0.1.0-preview.13-tvos-unsigned.ipa` and SHA-256 in the Preview 13 release
record apply only to that retained artifact, not a new private build.

1. Build, package and audit your private tvOS IPA as described in `TVOS.md`.
2. Re-sign the app and its nested `gGMSE01_recomp.dylib` with your own Apple
   development identity and bundle identifier, then install it on a paired
   Apple TV using Xcode or a compatible tvOS signing workflow.
3. Set `SUNPAD_TVOS_BUNDLE_IDENTIFIER` to the signed identifier before using
   any device script.
4. On your Mac, prepare your legally obtained GMSE01 USA revision-0 image with
   `scripts/prepare-game.sh`, then stage the extracted folder:

   ```sh
   ./scripts/stage-tvos-game-data.sh \
     "$PWD/ref/ModernGekko-Template/extracted/Super-Mario-Sunshine" \
     "Living Room"
   ```

5. Connect an Extended Gamepad before or after launching SunPad. The Siri
   Remote operates the setup screen but is not a gameplay controller.

The IPA contains the SunPad runtime and GMSE01 ahead-of-time recompiled module,
but no disc image, extracted assets, saves, signing identity, provisioning
profile, or device identifier. All filesystem-backed state is kept under
`Library/Caches/SunPad` and may be purged by tvOS. Back up configuration and
memory-card state before updating or deleting the app:

```sh
./scripts/backup-tvos-state.sh "Living Room" /absolute/path/to/new-backup
```

Collect diagnostics after a failure with `scripts/collect-tvos-diagnostics.sh`.
Review the output before sharing it. Never upload game data, saves, signing
material, device identifiers, or a complete app container.
