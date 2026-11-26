# Goal loop: SunPad on the new engine

- **Date:** 2026-11-26
- **Status:** for alignment. Nothing below has started. The maintainer
  assigns the goal after agreeing on it.
- **Replaces:** tasks E6 and E7 of [DECOMP-ENGINE-PLAN.md](DECOMP-ENGINE-PLAN.md)
  and the side-by-side beta. On 2026-11-26 the maintainer decided to replace
  the legacy engine entirely, with no legacy option in the app.

## Goal

Release the next SunPad with the decompilation engine as its only engine.
Players get it through PadMint, it installs over 0.3.x and keeps their saves
and settings, and iPhone, iPad, Apple TV and Mac each either work on the new
engine or are clearly marked unavailable. The legacy engine leaves the
repository, and a complete written record of what it was, how it worked and
how to bring it back stays behind, so the change can be reverted later.

Short form for assigning:

> Finish SunPad on the decompilation engine and release it, following
> docs/FINALIZE-NEW-ENGINE.md in chrissotraidis/sunpad: device-check the
> engine app, make it the SunPad app, record and then remove the legacy
> engine so it can be restored, update PadMint's recipe and catalog, rewrite
> README and the docs, and stop at each approval gate the document names.

## Done when

1. A copy built by PadMint from the published release installs over 0.3.x on
   the iPhone 14 and the iPad Pro, keeps the player's save and settings, and
   passes the [hands-on check](DECOMP-ENGINE-PLAN.md#hands-on-check).
2. PadMint's `scripts/player-check.sh` passes from PadMint's current `main`,
   with SunPad's clean checkout before tagging and without it after publishing.
3. `python3 ~/.codex/release-gate/release_gate.py` passes on every published
   artifact, and no published file contains game code.
4. The repository holds no legacy engine code, gitlinks, patches, scripts,
   tests or CI steps, and `check-repository.sh`, `dependency-lock.py` and CI
   pass on `main`.
5. `docs/LEGACY-ENGINE.md` exists and a reader could restore the
   legacy engine from it alone (card R1). The tag `legacy-engine-final`
   exists.
6. README, the docs, PadMint's catalog entry and its compatibility table
   describe the new engine, and nothing describes the legacy engine as
   current.
7. The maintainer approved the merge, the tag and the publish.

## Decisions

The loop uses these answers unless the maintainer changes them before
assigning it.

| ID | Decision | Answer used |
| --- | --- | --- |
| F1 | Version | 0.4.0. 0.3.3 (build 21) is on `main` but was never tagged or released, so 0.3.2 stays the last legacy release |
| F2 | Windows and Linux PadMint hosts | Mac only at release. PadMint tells Windows and Linux players that SunPad needs a Mac for now. Porting is a later task |
| F3 | Apple TV | Moved to the new engine in this release (card B4). If no Apple TV is available for its device check, it ships marked unavailable and B4 continues after the release |
| F4 | Mac app | The engine's own window with SunPad's keyboard layout. SunPad's own window and menus are a later task |
| F5 | App identity | The new engine takes over `com.sunpad.SunPad` and the name SunPad, so it updates 0.3.x in place |
| F6 | Legacy forks | ModernGekko, ModernGekko-tvOS and ModernGekko-Template stay on GitHub, untouched and unarchived, so a revert can use them |

## Rules

These come from AGENTS.md, CONTRIBUTING.md and the maintainer's standing
instructions, and hold for every card.

- Keep it simple and consistent with the app. After changing any menu item or
  button, recheck its wiring.
- Work in `/Users/chrissotraidis/.codex/worktrees/sunpad-engine-plan` on
  `codex/decomp-engine-plan` (draft PR #90). PadMint changes go in a
  worktree under `~/.codex/worktrees` from PadMint's `origin/main`, never in
  `~/GitHub/padforge`, which is on another branch with untracked files. No
  task clones in `~/GitHub`.
- The primary checkout `~/GitHub/sunpad` has a modified `ref/ModernGekko` and
  is behind `main`. Leave it untouched until the maintainer says otherwise.
- Engine changes go in the fork (chrissotraidis/sms-pc-port, branch `sunpad`)
  with its history and MIT notice intact. Update the gitlink and
  `config/dependencies.lock.json` together and run `dependency-lock.py`.
- Never publish an engine binary or anything with game code in it. Copy
  nothing from the unlicensed `sms-iphone-ipad` and `sms-android`.
- Preserve player data and signing state. Back up a device's saves to the Mac
  before installing over them. Never uninstall an app to get past a signing
  problem without asking.
- Every test launch on a device ends the session open there. Close test apps
  and shut down Simulators afterwards, and leave Simulators that were already
  running alone.
- Record source and CI results apart from device, gameplay and release
  results. A launch log does not prove gameplay.
- Wait for the maintainer before merging, tagging, publishing, pushing to
  PadMint's `main`, releasing PadMint, or sending anything to another person
  (the note to chasem-dev included).

## Starting state

| Item | State on 2026-11-26 |
| --- | --- |
| Engine | Fork `sunpad` at `bd9936f` on upstream `20abb7e`, pinned. Embedded library, retail UI, background pipelines, tvOS and device builds |
| App | `SunPadNext` target (`com.sunpad.SunPad.next`) next to the legacy `SunPad` and `SunPadTV` targets |
| Devices | iPhone 14 `00008110-001C2C641123A01E` and iPad Pro `00008112-001D485114DBC01E` have SunPad Next with the engine. The iPad also has SunPad 0.3.3 and a real save, backed up in `~/.codex/scratch/ipad-sunpad-backup-2026-11-23` |
| Signing | Identity `0D9207CDF3FA18B08D7B4EA62C7879BEB958185F`, profile `8b78a5eb-d835-41a7-9578-fbc74823f7e6`, team `VKDH2T9UTF`, `scripts/sign-dev-app.sh` |
| Measured | 30 FPS on both devices, no first-visit stutter, area-load hitches up to about 230 ms, iPad save migrated byte for byte |
| Unconfirmed | An in-game save written on a device, audio by ear, lock and unlock, 60 FPS, Apple TV, a PadMint-built copy |
| PadMint | `main` at 0.6.10. Supports `"when": "in-app"` inputs and the `upstream-engine` kind. SunPad's recipe is `padmint.json` in this repository, its catalog entry `catalog/sunpad.json` in PadMint |
| Last legacy commit | `72c101a` on `main` (0.3.3, unreleased). Last legacy release `v0.3.2` (`429a297`) |

## The loop

Repeat until every card is done or a stop condition holds.

1. Read this document's card table and the latest entries of
   [IMPROVEMENT-LOG.md](IMPROVEMENT-LOG.md).
2. Take the first card whose prerequisites are done and which does not wait
   for the maintainer. When every remaining card waits for the maintainer, ask
   for what it needs, say why, and keep working on anything else.
3. Do the card. Keep each commit to one purpose so it can be reverted alone.
4. Run the card's checks. A card is done only when its **Done when** holds.
5. Record the result in IMPROVEMENT-LOG.md (date, card, result, checks, what
   was not checked, next) and set the card's status here. Commit and push the
   PR branch.
6. Every third card, or after any device session, update PR #90's description
   and report to the maintainer in a few plain sentences.

Stop and report when:

- the same failure comes back three times on a card.
- a fix needs a decision this document does not answer.
- a check would need a device or the maintainer and nothing else is left to do.
- a card would cross an approval gate.

## Cards

| ID | Card | Needs | Status |
| --- | --- | --- | --- |
| A1 | In-game save on a device | maintainer | waiting |
| A2 | Area-load hitches | — | ready |
| A3 | Every area plays | — | ready |
| A4 | Hands-on check on both devices | A1, A2 | waiting |
| R1 | Record the legacy engine | — | ready |
| R2 | Mark the last legacy state | R1, maintainer | waiting |
| B1 | The engine becomes the SunPad app | A1 | blocked |
| B2 | Upgrade over 0.3.x | B1 | blocked |
| B3 | Remove the legacy engine | B1, R2 | blocked |
| B4 | Apple TV | B1 | blocked |
| B5 | Mac app | B1 | blocked |
| B6 | Published app and its audits | B3 | blocked |
| C1 | PadMint recipe | B6 | blocked |
| C2 | PadMint catalog and docs | C1 | blocked |
| C3 | Player check before tagging | C2, D1 | blocked |
| D1 | Documentation | B3 | blocked |
| D2 | Merge | C3, maintainer | blocked |
| D3 | Release | D2, maintainer | blocked |
| D4 | After the release | D3 | blocked |

### Phase A: finish the engine app

**A1 In-game save on a device.** The maintainer saves from the pause menu,
closes SunPad from the app switcher, reopens and loads, then tries Export
Saves and imports that file back. The loop then copies the engine card off the
device. **Done when** the card's files changed after the save, the loaded file
shows the new progress, and the exported GCI imports back. Everything in phase
B waits on this card, because a broken save would stop the release.

**A2 Area-load hitches.** The maintainer's iPhone session had one pipeline
still made while playing (227 ms) and an area load that uploaded 130 textures
in one frame (233 ms). Find why that pipeline skipped the background path, and
spread load-time texture uploads across frames in the fork if that holds up.
**Done when** a cold first visit to Delfino Plaza, Bianco Hills and Ricco
Harbor on the iPhone 14 has no frame over 100 ms once the area plays.

**A3 Every area plays.** Warp into each of the nine areas (Delfino Plaza,
Airstrip, Bianco Hills, Ricco Harbor, Gelato Beach, Pinna Park, Sirena Beach,
Noki Bay, Pianta Village) on the iPhone 14 for 60 seconds each, with a mirrored
screenshot and the engine log. **Done when** each reaches play at 30 FPS with
nothing visibly wrong. A fault in the game itself goes upstream to sms-pc-port
as a report with a capture, drafted for the maintainer to send.

**A4 Hands-on check.** The maintainer runs the checklist in the engine plan on
both devices, with touch and with a controller, including the three-dot menu,
audio by ear, 60 FPS, and locking the device mid-game. **Done when** each step
is recorded as passed or as an issue with a card.

### Phase R: keep the way back

**R1 Record the legacy engine.** Write `docs/LEGACY-ENGINE.md`
before anything is removed, from the code and the docs as they stand at
`72c101a`. It covers:

- **What it was.** The game's PowerPC code translated ahead of time into C
  (about 226 MB generated, an 81 MB module) running in ModernGekko, a fork of
  Dolphin's core, with Dolphin's Metal renderer, DSP emulation and DiscIO.
- **How it was built.** Every script in order, from `prepare-game.sh`
  (SHA-256 check, extraction, module generation) through
  `ios-build-core-device.sh`, `package-ios.sh`, the Windows and Linux module
  builders and the tvOS and Mac scripts, with inputs, outputs, tools and
  times.
- **How it ran.** `SunPadCoreHost`, the input pipe and `gcpipe.py`, the
  provisioned module and dev config, on-device extraction with
  `SunPadDiscExtractor`, save locations, settings and their Dolphin keys,
  lifecycle and audio handling, diagnostics.
- **Every component removed**, with its path, its pinned revision and
  repository URL from the lock (ModernGekko, ModernGekko-tvOS,
  ModernGekko-Template and their nested repositories), the patches in
  `patches/`, and the tests.
- **PadMint.** The legacy `padmint.json` in full, the catalog entry as it
  was, and the Windows and Linux host notes.
- **What it measured.** iPhone 14 at 25.7 to 27.1 FPS and down to 0.759 speed,
  the rejected 90% clock and dual-core experiments, the 60 FPS patch result,
  memory, and the issues players reported.
- **How to bring it back.** Two routes, tested as far as they can be without
  undoing the release: rebuilding 0.3.2 or `legacy-engine-final` as it was,
  and reverting the removal commits on `main` (which commits, in which order,
  and what must be restored outside the repository, such as PadMint's catalog
  entry).

**Done when** the document names every file B3 will delete and each
statement can be traced to the code or a dated measurement.

**R2 Mark the last legacy state.** With the maintainer's approval, push the
annotated tag `legacy-engine-final` on `72c101a` and a branch
`legacy-engine` at the same commit. Record both in LEGACY-ENGINE.md. **Done
when** both exist on GitHub and a clean clone at the tag runs
`bootstrap-dependencies.sh --sources-only` successfully.

### Phase B: make it the SunPad app

**B1 The engine becomes the SunPad app.** The `SunPad` target takes
`SunPadEngineHost.mm`, MoltenVK and the engine embed phase, keeps
`com.sunpad.SunPad` and the name SunPad, and the `SunPadNext` target goes.
The engine's three-dot menu becomes the only menu, with every item's wiring
rechecked. Version 0.4.0, build 22. **Done when** the app builds for devices
and the Simulator, plays the plaza route, and its menu items each do what they
say.

**B2 Upgrade over 0.3.x.** Back up the iPad's 0.3.3 save again, then install
the new build over SunPad 0.3.3 there. **Done when** the save migrates and loads
in game, the Dolphin card is unchanged, the touch layout and settings carry
over, the legacy experiment settings are reset, and Remove Stored Game Data
also removes the extracted game files 0.3.x left (about 1.4 GB).

**B3 Remove the legacy engine.** In separate commits, in this order, each
passing `check-repository.sh`:

1. App code: `SunPadCoreHost`, `SunPadDiscExtractor`,
   `SunPadInputPipeEncoder`, and every `SUNPAD_DECOMP_ENGINE` branch, keeping
   the engine side.
2. Scripts: `prepare-game.sh`, `build-ios-module.sh`, `ios-build-core*.sh`,
   `tvos-build-core-*.sh`, `ios-provision*.sh`, `tvos-provision-device.sh`,
   `fetch-gmse01-symbols.sh`, `audit-generated-gmse01.sh`, `stage1-*.sh`,
   `gcpipe.py`, `sunpad-capture.py`, `bench-route.sh`,
   `package-macos-app.sh`, the legacy toolchain files and `scripts/windows/`,
   with their tests.
3. Gitlinks and lock entries for `ref/ModernGekko`, `ref/ModernGekko-tvOS`
   and `ref/ModernGekko-Template`, and `patches/`.
4. CI steps that build the legacy engine.
5. Renames: `SunPadEngineHost` keeps its file, `package-ios-next.sh` and
   `package-macos-next.sh` lose "next".

**Done when** nothing in the repository refers to the removed names outside
LEGACY-ENGINE.md and the historical documents, and `check-repository.sh`,
`dependency-lock.py` and CI pass.

**B4 Apple TV.** `SunPadTVAppDelegate` moves to the engine host, with the
engine built for tvOS and the controller-only input SunPadTV has today.
**Done when** an Apple TV reaches play with a controller and a save survives a
relaunch. Without an Apple TV for the check, SunPadTV ships marked
unavailable (F3) and this card stays open.

**B5 Mac app.** `package-macos.sh` (from `package-macos-next.sh`) builds
SunPad.app with the engine's window and SunPad's keyboard layout. **Done
when** a clean build plays on the maintainer's Mac and a 0.3.x Mac save carries
over with the original left in place.

**B6 Published app and its audits.** `package-ios.sh` makes the app with no
engine inside, and `audit-ios-package.sh` checks a player's copy (the engine
library's nested signature, arm64, iOS 16 minimum, expected imports only).
**Done when** both audits pass and `release_gate.py` passes on the published
app.

### Phase C: PadMint

**C1 PadMint recipe**, `padmint.json` in this repository.

- `kind`: `upstream-engine`.
- Input: the GMSE01 disc with `"when": "in-app"`. The build never reads it,
  so PadMint no longer asks for it, and the app imports it on the device.
- iPhone hosts: `macos-arm64` only (F2). Mac target: `macos-arm64`.
- Tools: git, cmake, ninja and Homebrew `llvm` (its clang loads the engine's
  pointer pass), with the note "brew install llvm". Full Xcode stays required
  for signing.
- Steps: fetch the engine sources, `build-engine.sh iphoneos`, put the
  library in the published app and sign it, for iPhone, and the Mac
  equivalent.
- `requirements.disk_gb` from a measured clean build (the engine build
  directory is about 0.7 GB, its sources 1.4 GB).

**Done when** PadMint validates the recipe and a PadMint build from a clean
checkout produces an app that plays on a device.

**C2 PadMint catalog and docs**, on a PadMint branch. `catalog/sunpad.json`:
notes, `ios_hosts`, Windows and Linux notes, `free_space_gb`,
`player_next` (import your disc in SunPad's menu), `player_help`. The SunPad
rows in `docs/COMPATIBILITY.md` and any SunPad lines in `STATUS.md` and
`docs/DECISIONS.md`. **Done when** PadMint's tests pass and the PR is open
for the maintainer.

**C3 Player check before tagging.** `scripts/player-check.sh` from PadMint's
`main` with SunPad's clean checkout, Apple's Python 3.9 and an empty PadMint
folder. If C2 has not merged, run it with the PadMint branch and again after
it merges. **Done when** it passes. A failure blocks the release.

### Phase D: documentation and release

**D1 Documentation.** Rewrite README (what SunPad is now, getting it through
PadMint with the new requirements, importing the disc, upgrading from 0.3.x,
devices, known issues, credits), ARCHITECTURE, BUILDING, DEPENDENCIES,
IOS_IPADOS, MACOS, TVOS, CONTROLS, STATUS, KNOWN_ISSUES, TECH-DEBT, TESTING,
LEGAL_AND_PROVENANCE, CREDITS, THIRD_PARTY_NOTICES (Dolphin-derived entries
out, the engine's in), AGENTS, CLAUDE and CONTRIBUTING, and write
RELEASE-0.4.0.md. Documents about the legacy engine's research and releases
(IMPROVEMENT-PLAN, APPLE-PERFORMANCE-RESEARCH, SMS-PC-PORT-REVIEW, AUDIO_ISSUE,
IOS27_STARTUP, PREVIEW-13, the earlier RELEASE notes) get a dated note at the
top that they describe the legacy engine, with a link to LEGACY-ENGINE.md.
**Done when** `check-markdown-links.py` passes and no document describes the
legacy engine as current.

**D2 Merge.** With the maintainer's approval, PR #90 into `main`, and the
PadMint PR.

**D3 Release.** With the maintainer's approval: tag `v0.4.0`, publish the
apps with no engine inside, run `release_gate.py` on each artifact and
`player-check.sh` without SunPad's checkout. **Done when** a PadMint-built
copy from the published release installs over 0.3.x and plays on a device.

**D4 After the release.** PadMint's compatibility row records the result.
Windows and Linux hosts, Apple TV (if B4 is open) and the SunPad-window Mac
app become their own task cards. The upstream note to chasem-dev waits for the
maintainer to send it.

## Reverting later

Until R1 and R2 are done, nothing is removed. After the release, the way back
is in LEGACY-ENGINE.md. In short, PadMint's catalog entry goes back to its
recorded form, and either 0.3.2 is rebuilt from its tag, or the B3 commits are
reverted on `main` and the legacy gitlinks restored from the lock entries
recorded there.
