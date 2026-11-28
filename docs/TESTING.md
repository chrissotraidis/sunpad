# Testing

Last updated: 28 November 2026, for SunPad 0.4.0. The legacy engine's test
record (August to November 2026: Simulator and device evidence, the HDMI and
controller crash, tvOS previews, the Mac app and the fork migration) is in
[TESTING.md at legacy-engine-final](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/TESTING.md).

## Principles

- A build that compiles isn't a game that plays. Gameplay claims need a route
  or hands-on play on the named device, with the date.
- Keep source checks, package audits, device checks and player reports
  apart, and say which one a result came from.
- Back up a device's SunPad container before installing over it, and run
  test routes on a scratch card (`SMS_SAVE_DIR`) when the device holds a real
  save.
- Never commit or attach game data, saves, engine binaries, signing material
  or a device container.

## Game under test

Super Mario Sunshine USA revision 0 (`GMSE01`), 1,459,978,240 bytes, SHA-256
`67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d` as checked
by the app (`SunPadSupportedImageSHA256`).

## Source checks

```sh
./scripts/check-repository.sh
```

It runs `git diff --check`, the dependency lock and its test, shell, Python,
plist and asset syntax, the Markdown link check, the focused tests below, the
package auditor's rejection test, and the scans for tracked game data,
binaries, credentials and personal paths.

| Test | Covers |
| --- | --- |
| `tests/test-engine-bridge.sh` | SunPad settings to `SMS_*` variables, input to the GameCube pad |
| `tests/test-engine-saves.sh` | Dolphin GCI to the engine's card and back, byte for byte, and migration that never changes the Dolphin card |
| `tests/test-save-transfer.sh` | Save export and import validation |
| `tests/test-controller-mapping.sh`, `test-controller-slots.sh`, `test-controller-rumble.sh` | Controller mapping, player slots and rumble |
| `tests/test-diagnostics.sh` | Logs, redaction and the problem report, including the engine log |
| `tests/test-game-data-setup.sh` | Game-data import wiring |
| `tests/test-iphone-touch-layout-defaults.sh` | iPhone touch layout defaults |
| `tests/test-ipa-module.sh` | The package audit rejects an unrelated library as the engine |

CI ([repository-checks.yml](../.github/workflows/repository-checks.yml)) runs
the source checks, builds and audits the published app, and builds the
device engine with Homebrew LLVM. It doesn't play the game.

## Builds and packages

- `scripts/build-engine.sh iphoneos` and `iphonesimulator`.
- `scripts/build-ios-app.sh`: the published app, audited with
  `SUNPAD_APP_ONLY=1`.
- `scripts/package-ios.sh PUBLISHED.ipa ENGINE`: a player's copy, audited.
- `python3 ~/.codex/release-gate/release_gate.py FILE` on every file to be
  published (maintainer's release gate).
- PadMint's `scripts/player-check.sh sunpad ios - SUNPAD_CHECKOUT PUBLISHED.ipa`
  from PadMint's `main` before tagging, and `scripts/player-check.sh sunpad ios -`
  without a checkout after publishing. It uses Apple's Python 3.9 and an empty
  PadMint folder, as players do.

## Routes

`scripts/run-engine-route.sh DEVICE plaza|bianco|ricco|gelato [SECONDS]`
starts a new file, warps to the area and prints the engine's frame
statistics. A healthy 30 FPS run shows 33.4 ms per frame.

## Device evidence

| Date | Device | Build | Result |
| --- | --- | --- | --- |
| 23 Nov 2026 | iPad Pro 12.9-inch (M2), iPadOS 27.2.1 | SunPad Next | Delfino Plaza at 33.4 ms per frame, 2×, 450 MiB resident. The iPad's 0.3.3 save migrated and matched byte for byte. Touch layout and settings carried over from restored preferences |
| 23 Nov 2026 | iPad Pro | SunPad Next | The maintainer played with an Xbox controller at 2× and 4×: better than 0.3.3, with stutter at first loads, fixed below |
| 23 Nov 2026 | iPhone 14 (A15), iOS 27.2.1 | SunPad Next, engine `bd9936f` | Memory probe: game memory at `0x7000000000`, limit `0x7180000000`. Delfino Plaza and Bianco Hills at 33.4 ms per frame at 1×. Bianco Hills from a cold cache made 164 pipelines in the background, slowest frame in play 37 ms |
| 26 Nov 2026 | iPhone 14 | SunPad Next, engine `bd9936f` | The maintainer played and found it substantially better than 0.3.3. Slowest area-load frame 232.8 ms (130 texture uploads) |
| 28 Nov 2026 | iOS Simulator (iPhone 17e) | SunPad 0.4.0 build 22 | Plaza route at 33.4 ms per frame. Save from the pause menu on a scratch card, relaunch showed file A with one Shine, load left the card unchanged, GCI export and import byte-identical |
| 28 Nov 2026 | iPad Pro, iPadOS 27.2.1 | SunPad 0.4.0 build 22 over 0.3.3 | The migrated 94-Shine save loads into Delfino Plaza at 30 FPS. A scratch-card save from the pause menu reloads at file select. Sirena Beach holds 33.4 ms per frame at 2× |
| 28 Nov 2026 | iOS Simulator (iPhone 17e) | SunPad 0.4.0 build 22 | Every area from a new game (`SMS_WARP=0..9,0`, `SMS_WARP_DIRECT=1`, scratch card, 55 s each): Airstrip, Delfino Plaza, Bianco Hills, Ricco Harbor, Gelato Beach, Pinna Park, Sirena Beach, Delfino Hotel, Pianta Village and Noki Bay load and draw correctly with no fault. All held 33.4 ms per frame except Sirena Beach, at 47 to 69 ms with up to 122 render passes per frame, the game waiting up to 365 ms on the renderer thread |

## SunPad 0.4.0 release checks

| Check | Result |
| --- | --- |
| `check-repository.sh` and `dependency-lock.py` | Pass after every removal commit |
| Published app and player copy audits | Pass |
| PadMint `check-manifest`, `plan` and catalog audit | Pass |
| PadMint `player-check.sh` with SunPad's checkout | Pass at `5de8a54` and again at `0439e8f` with PadMint `0e4b696` (28 November), after fixes to packaging (`4f6f98b`) and the audit (`5de8a54`) |
| `release_gate.py` on the published app | Pass, 0 address-named functions (build from `9553186`) |
| Upgrade over 0.3.3 on the iPad Pro | Pass. The save migrated byte for byte, the Dolphin card is unchanged, file select shows the iPad's files (1 and 94 Shines), and the 94-Shine file loads into Delfino Plaza at 30 FPS with the iPad's touch layout and 2× setting. Loading didn't change the card |
| Save cycle on the iPad Pro | Pass on a scratch card (`SMS_SAVE_DIR`): a new file saved from the Delfino Plaza pause menu, the card changed, and a relaunch showed file A with 1 Shine where it had shown New |
| Sirena Beach on the iPad Pro | 33.4 ms per frame at 2× with up to 119 render passes, nominal thermal state |

[FINALIZE-NEW-ENGINE.md](FINALIZE-NEW-ENGINE.md) lists the checks still to
run before publishing, and this table gains their results.

## Hands-on checklist

On each device, with the build under test:

1. First launch over 0.3.x: the save shows at file select, settings and
   touch layout are as before.
2. Every three-dot menu item does what it says ([control guide](CONTROLS.md)).
3. Touch: movement, camera, R pressure along the slider, Start, Move mode.
4. A controller: auto-hide, mapping, rumble.
5. Save in game, close SunPad from the app switcher, reopen, load.
6. Background and return during play, and a call or Siri.
7. Export Saves, then Import Dolphin Save with the exported file.
8. Report a Problem: the report contains the engine log.
9. Remove Stored Game Data and import again.
