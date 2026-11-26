# Finalizing SunPad on the new engine

- **Date:** 2026-11-26
- **Status:** draft for the maintainer's approval
- **Replaces:** the side-by-side beta in [DECOMP-ENGINE-PLAN.md](DECOMP-ENGINE-PLAN.md)
  tasks E6 and E7. The maintainer decided on 2026-11-26 to replace the legacy
  engine entirely, with no legacy option, because the new engine plays better
  on every device tested and nobody uses the old one.

## Goal

SunPad's next release runs only the decompilation engine. Players get it
through PadMint as they do today. It installs over 0.3.x and keeps their saves
and settings. The legacy engine and everything that builds it are gone from the
repository.

The goal is met when all of these hold:

1. PadMint's `scripts/player-check.sh` passes for the release, with SunPad's
   clean checkout before tagging and without it after publishing.
2. A PadMint-built copy installs over 0.3.x on the iPhone 14 and the iPad Pro,
   keeps the player's save, and passes the [hands-on check](DECOMP-ENGINE-PLAN.md#hands-on-check).
3. `release_gate.py` passes on the published app.
4. The repository holds no legacy engine code, gitlinks, scripts or tests, and
   `check-repository.sh` and CI pass.
5. README, the docs, PadMint's catalog entry and its compatibility table
   describe the new engine.
6. The maintainer approves publishing.

## Decisions needed before phase B

| ID | Decision | Recommendation |
| --- | --- | --- |
| F1 | Version number | 0.4.0. The engine changes but the app, its controls and the PadMint route stay, and Apple TV and other hosts are not at 1.0 parity yet |
| F2 | Windows and Linux PadMint hosts, which 0.3.x supports as experimental | Mac only at release. The engine build needs Homebrew LLVM with its pass plugins, which has never been tried off a Mac. PadMint tells Windows and Linux players SunPad needs a Mac for now. Porting follows as its own task |
| F3 | Apple TV, whose app runs on the legacy engine | Port it in this release (card B4). The engine already builds for tvOS. If the Apple TV is not available for a device check, ship iPhone and iPad first and mark Apple TV unavailable until it is |
| F4 | The Mac app | Ship the engine's own window with SunPad's keyboard layout (`package-macos-next.sh`, already playing on the maintainer's Mac). A Mac app with SunPad's window and menus comes later |
| F5 | App identity | The new engine takes over `com.sunpad.SunPad`, so it updates 0.3.x in place. SunPad Next's separate identity goes away |

## The loop

Each pass through the loop:

1. Take the first card below whose prerequisites are met.
2. Do it in the task worktree on the PR branch (PadMint changes on a PadMint
   branch from its `main`).
3. Run the card's check. Device checks need the maintainer or an unlocked
   device, and every test launch ends the session open on that device.
4. Record the result in [IMPROVEMENT-LOG.md](IMPROVEMENT-LOG.md) and the card's
   row below.
5. When a check fails, fix it and run the card again. Stop and report when the
   same failure comes back three times or the fix needs a decision.

Merging, tagging, publishing and pushing to PadMint's `main` each wait for
the maintainer's go-ahead. The primary checkout at `~/GitHub/sunpad` has a
modified `ref/ModernGekko`, which stays untouched until the maintainer says
otherwise.

## Cards

| ID | Card | Needs | Status |
| --- | --- | --- | --- |
| A1 | In-game save on a device | — | waiting for the maintainer |
| A2 | Remaining hitches | — | ready |
| A3 | Every hub area plays | A2 | ready |
| A4 | Hands-on check on both devices | A1 | waiting for the maintainer |
| B1 | The engine becomes the SunPad app | A1, F1, F5 | blocked |
| B2 | Upgrade over 0.3.x | B1 | blocked |
| B3 | Remove the legacy engine | B1, F3 | blocked |
| B4 | Apple TV | B1, F3 | blocked |
| B5 | Mac app | B1, F4 | blocked |
| B6 | Published app and its audits | B3 | blocked |
| C1 | PadMint recipe | B6, F2 | blocked |
| C2 | PadMint catalog and docs | C1 | blocked |
| C3 | Player check before tagging | C2 | blocked |
| D1 | Documentation | B3 | blocked |
| D2 | Merge | C3, D1 | blocked |
| D3 | Release | D2 | blocked |
| D4 | After the release | D3 | blocked |

### Phase A: finish the engine app

**A1 In-game save on a device.** The iPhone's engine card has not changed since
its first launch, so no in-game save has been confirmed on a device. Save from
the pause menu, close SunPad from the app switcher, reopen and load. Then
Export Saves and import that file back. Check: the card's files change after
the save, and the loaded file shows the new progress. Everything after this
card depends on it.

**A2 Remaining hitches.** Two causes remain in the maintainer's iPhone session.
One pipeline was still built while playing (227 ms), and an area load uploaded
130 textures in one frame (233 ms). Find why the first was not made in the
background, and spread texture uploads at loads across frames if that holds up.
Check: a cold first visit to Delfino Plaza, Bianco Hills and Ricco Harbor on the
iPhone 14 has no frame over 100 ms once the area is playing.

**A3 Every hub area plays.** Warp into each of the eight areas (Delfino Plaza,
Airstrip, Bianco Hills, Ricco Harbor, Gelato Beach, Pinna Park, Sirena Beach,
Noki Bay, Pianta Village) on the iPhone 14, 60 seconds each with a mirrored
screenshot. Check: each reaches play at 30 FPS with nothing visibly wrong. A
problem in the game itself goes upstream to sms-pc-port as a report with a
capture.

**A4 Hands-on check.** The checklist in the engine plan on both devices, by the
maintainer, with touch and with a controller. It includes the new three-dot
menu, audio by ear, and locking the device mid-game.

### Phase B: make it the SunPad app

**B1 The engine becomes the SunPad app.** The `SunPad` target takes
`SunPadEngineHost.mm`, MoltenVK and the engine embed phase, keeps
`com.sunpad.SunPad` and the display name SunPad, and the `SunPadNext` target
goes. Set the version (F1). Check: the app builds for the device and the
Simulator and plays the plaza route.

**B2 Upgrade over 0.3.x.** The iPad Pro still has SunPad 0.3.3 with a real save.
Install the new build over it. Check: the save migrates, the Dolphin card is
unchanged, touch layout and settings carry over, and Remove Stored Game Data
also removes the extracted game files 0.3.x left behind (about 1.4 GB).

**B3 Remove the legacy engine.**

- Gitlinks and lock entries for `ref/ModernGekko`, `ref/ModernGekko-tvOS`
  and `ref/ModernGekko-Template`. The forks stay on GitHub with their history.
- `patches/`, and the module and translation scripts: `prepare-game.sh`,
  `build-ios-module.sh`, `ios-build-core*.sh`, `tvos-build-core-*.sh`,
  `ios-provision*.sh`, `tvos-provision-device.sh`, `fetch-gmse01-symbols.sh`,
  `audit-generated-gmse01.sh`, `stage1-*.sh`, `gcpipe.py`,
  `sunpad-capture.py`, `bench-route.sh`, `package-macos-app.sh`, the
  toolchain files and `scripts/windows/`.
- App code: `SunPadCoreHost`, `SunPadDiscExtractor`,
  `SunPadInputPipeEncoder`, the Dolphin defaults in `apple/macos`, and every
  `SUNPAD_DECOMP_ENGINE` branch, keeping the engine side. The legacy menu goes
  with them.
- Tests for removed code, and the CI steps that build the legacy engine.

Check: no reference to the removed names remains, and `check-repository.sh`,
`dependency-lock.py` and CI pass.

**B4 Apple TV.** `SunPadTVAppDelegate` moves to the engine host, with the
engine built for tvOS. Check: the Apple TV reaches play with a controller, and
a save survives a relaunch. Follows F3.

**B5 Mac app.** `package-macos-next.sh` becomes the Mac packaging script,
named SunPad. Check: a clean Mac build plays, and a 0.3.x Mac save carries over.
Follows F4.

**B6 Published app and its audits.** `package-ios.sh` makes the app with no
engine inside, and `audit-ios-package.sh` checks the engine library a player's
copy adds (nested signing, arm64, iOS 16 minimum, expected imports only). Check:
both audits pass and `release_gate.py` passes on the published app.

### Phase C: PadMint

**C1 PadMint recipe** (`padmint.json` in this repository).

- `kind`: `upstream-engine`.
- Input: the GMSE01 disc with `"when": "in-app"`. The engine reads it on the
  device and the build never touches it, so PadMint no longer asks for it.
- iPhone hosts: `macos-arm64` (F2).
- Tools: git, cmake, ninja and Homebrew `llvm`, whose clang can load the
  engine's pointer pass, with a player note to run `brew install llvm`.
  BananaPad already asks for Homebrew LLVM.
- Steps: fetch the engine sources, `build-engine.sh iphoneos`, then put the
  library into the published app and sign it.
- Measure a clean build's time and disk use on a Mac and set
  `requirements.disk_gb` from it (the engine build directory is about 0.7 GB).

Check: `python3 -m padmint` validates the recipe, and a PadMint build from a
clean checkout produces an app that plays.

**C2 PadMint catalog and docs** (in chrissotraidis/padmint, on a branch).
`catalog/sunpad.json`: the notes, `ios_hosts`, the Windows and Linux notes,
`free_space_gb` and the next steps for players. The SunPad rows in
`docs/COMPATIBILITY.md`. Check: PadMint's tests pass.

**C3 Player check before tagging.** From PadMint's current `main`, with
SunPad's clean checkout. A failure blocks the release.

### Phase D: documentation and release

**D1 Documentation.** README (getting SunPad, requirements, what changed),
ARCHITECTURE, BUILDING, DEPENDENCIES, IOS_IPADOS, MACOS, TVOS, STATUS,
KNOWN_ISSUES, TECH-DEBT, TESTING, LEGAL_AND_PROVENANCE, CREDITS and
THIRD_PARTY_NOTICES (Dolphin-derived entries out, the engine's in), AGENTS and
CONTRIBUTING, and release notes. Documents about the legacy engine's research
(the improvement plan, performance research, the October review) are marked
historical. Check: `check-markdown-links.py` passes and no document describes
the legacy engine as current.

**D2 Merge.** PR #90 into `main` after the maintainer approves.

**D3 Release.** Tag, publish the app with no engine inside, and run the player
check without SunPad's checkout. A PadMint-built copy from the published release
installs and plays on a device. The maintainer approves the publish.

**D4 After the release.** PadMint's compatibility row records the result.
Windows and Linux hosts and the SunPad-window Mac app become their own tasks.
The note to chasem-dev about the embedded host backend goes out when the
maintainer sends it.

## Size

Phase A is a day of work plus the maintainer's device sessions. Phase B is
about three days, most of it B3 and B4. Phase C is a day plus a clean Mac build
for the player check. Phase D is a day, then the release itself.
