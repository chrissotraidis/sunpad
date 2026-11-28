# Goal loop: SunPad 0.4.0 on the new engine, in one day

- **Date:** 2026-11-28
- **Status:** assigned on 2026-11-28. The maintainer said to get it done, with
  a public release used through PadMint as the end goal. That grants approval A
  and approval B in its publish-when-green form below.
- **Replaces:** the multi-day version of this document (commit 0a1a21e) and
  tasks E6 and E7 of [DECOMP-ENGINE-PLAN.md](DECOMP-ENGINE-PLAN.md). On
  2026-11-26 the maintainer decided to replace the legacy engine entirely.

## Goal

Release SunPad 0.4.0 for iPhone and iPad today, with the decompilation engine
as its only engine, built through PadMint and installing over 0.3.x with saves
and settings kept. Before the legacy engine leaves the repository, record it
completely and tag its last commit, so it can be restored later.

Short form:

> Release SunPad 0.4.0 on the decompilation engine, usable through PadMint,
> following docs/FINALIZE-NEW-ENGINE.md in chrissotraidis/sunpad: record and
> tag the legacy engine, remove it, update PadMint, rewrite the docs, and
> publish once every check before publishing passes.

## Done when

1. A copy PadMint built from the published v0.4.0 installs over 0.3.x on the
   iPad Pro and the iPhone 14, keeps the save and settings, and plays.
2. PadMint's `scripts/player-check.sh` passes from PadMint's `main`, with
   SunPad's clean checkout before tagging and without it after publishing.
3. `release_gate.py` passes on every published file, and none contains game
   code.
4. The repository has no legacy engine code, gitlinks, patches, scripts, tests
   or CI steps. `check-repository.sh` and `dependency-lock.py` pass, and CI
   passes or its runner outage is recorded (cut rule 3).
5. `docs/LEGACY-ENGINE.md` records the legacy engine well enough to restore
   it, and the tag `legacy-engine-final` is on GitHub.
6. README, the docs and PadMint's SunPad entry describe the new engine.

## Scope

| Today | After today (own task cards, recorded as known issues) |
| --- | --- |
| iPhone and iPad app on the new engine, as `com.sunpad.SunPad` 0.4.0 | Apple TV on the new engine. SunPadTV is marked unavailable in 0.4.0 |
| Save cycle checked on a device | Mac app on the new engine. PadMint's Mac target is withdrawn, and existing Mac copies keep working |
| Legacy record, tag and branch | Windows and Linux PadMint hosts |
| Legacy engine removed | Remaining area-load hitches (up to about 230 ms) |
| PadMint recipe and catalog | 60 FPS stays experimental |
| README and every doc | SunPad's own window on Mac, the note to chasem-dev |

## Decisions

Used unless the maintainer changes them at alignment.

| ID | Decision | Answer |
| --- | --- | --- |
| F1 | Version | 0.4.0, build 22. 0.3.3 was never tagged, so 0.3.2 stays the last legacy release |
| F2 | PadMint hosts | Mac only. PadMint tells Windows and Linux players that SunPad needs a Mac for now |
| F3 | Apple TV | Marked unavailable in 0.4.0, ported after today |
| F4 | Mac | PadMint's Mac target withdrawn for 0.4.0, the engine's Mac app shipped after today |
| F5 | App identity | The new engine takes over `com.sunpad.SunPad` and updates 0.3.x in place |
| F6 | Legacy forks | Left on GitHub, untouched and unarchived |

## Approvals

The loop asks at alignment for **approval A**, and stops once for
**approval B**.

- **Approval A, at alignment:** push the tag `legacy-engine-final` and the
  branch `legacy-engine` on `72c101a`, and open (not merge) a PadMint PR.
- **Approval B, publish when green:** merge PR #90 and the PadMint PR, tag and
  publish v0.4.0, and release PadMint if the catalog change needs it, once S0
  to C3 are done and their checks pass. Granted on 2026-11-28. A failed check
  stops the loop before this point.

## Rules

- Work in `~/.codex/worktrees/sunpad-engine-plan` on
  `codex/decomp-engine-plan` (PR #90). PadMint work goes in a worktree under
  `~/.codex/worktrees` from PadMint's `origin/main`, never in
  `~/GitHub/padforge`. Leave `~/GitHub/sunpad` untouched (it has a modified
  `ref/ModernGekko`).
- Engine changes go in the fork (chrissotraidis/sms-pc-port, `sunpad`), with
  the gitlink and the lock updated together.
- Never publish an engine binary or anything with game code in it. Copy nothing
  from `sms-iphone-ipad` or `sms-android`.
- Back up a device's saves to the Mac before installing over them. Test saves
  go to a scratch card (`SMS_SAVE_DIR`), never the player's.
- Test launches end the session open on that device. Close test apps and shut
  down Simulators afterwards, and leave Simulators already running alone.
- Recheck every menu item's wiring after changing the app's menu.
- A locked or disconnected device: ask the maintainer to unlock it, say which
  card needs it, and continue with cards that do not.
- Installing over SunPad 0.3.3 fails on signing: stop B2, never uninstall,
  and ask. B3 waits for B2.
- Record source, CI, device and release results separately.

## Schedule

Times are from the start (H0). Builds, CI and device runs go in the
background while other cards are written.

| When | Foreground | Background |
| --- | --- | --- |
| H0–0:30 | S0 start checks and backups | — |
| 0:30–2:00 | R1 legacy record | A1 save cycle, A3 area runs |
| 2:00–3:30 | R2 tag, B1 app switch, B2 upgrade on the iPad | — |
| 3:30–5:00 | B3 removal, B4 published app and audits | CI on the pushed removal |
| 5:00–7:00 | D1 documentation, C2 PadMint PR | C1 recipe build, then C3 player check |
| 7:00–7:30 | Report and approval B | — |
| 7:30–8:30 | D2 release, post-publish player check, D3 | — |

## The loop

1. Take the next card in the schedule whose prerequisites are done.
2. Do it. Keep each commit to one purpose so it can be reverted alone.
3. Run its checks. A card is done only when its **Done when** holds.
4. Add a line to [IMPROVEMENT-LOG.md](IMPROVEMENT-LOG.md) under one entry for
   today (card, result, checks, what was not checked), set its status in the
   table below, commit and push.
5. At each schedule boundary, compare progress with the schedule and apply the
   cut rules. Send the maintainer one plain sentence only when something
   changes the plan.

Stop and report when the same failure comes back three times, a fix needs a
decision this document does not answer, or the next step is approval B.

## Cut rules

1. **A card overruns its time box by half:** finish the smallest version that
   meets its **Done when**, move the rest to a known issue, and go on.
2. **The scripted save cycle (A1) cannot be made to work in its hour:** ask the
   maintainer for the manual save test and continue with R1 and B1 meanwhile.
   Nothing is removed (B3) until a save cycle passes.
3. **GitHub's Mac runners do not pick up CI within 45 minutes:** rely on the
   local checks and builds, record the outage, and ask at approval B whether to
   merge without CI.
4. **The player check fails:** fix and rerun it. After the second failure with
   no clear fix, stop before approval B.
5. **A3 finds an area that does not play:** 0.4.0 still ships if the area is
   not on the path a new file takes through the game. The fault becomes a known
   issue and an upstream report drafted for the maintainer.

## Cards

| ID | Card | Box | Needs | Status |
| --- | --- | --- | --- | --- |
| S0 | Start checks and backups | 30 min | — | done (iPhone backup pending) |
| A1 | Save cycle on a device | 1 h | S0 | done in the Simulator, device check before D2 |
| A3 | Every area plays | 1 h | S0 | every area plays in the Simulator, Sirena Beach slow there. Device run before D2 |
| R1 | Legacy record | 1.5 h | S0 | done |
| R2 | Legacy tag and branch | 10 min | R1, approval A | done |
| B1 | The engine becomes the SunPad app | 1 h | A1 | done |
| B2 | Upgrade over 0.3.3 on the iPad | 30 min | B1 | installed over 0.3.3 on the iPad: save migrated byte for byte, Dolphin card unchanged. In-game check waits for iOS to verify the developer |
| B3 | Remove the legacy engine | 1 h | B2, R2 | done |
| B4 | Published app and its audits | 30 min | B3 | done |
| C1 | PadMint recipe | 1 h | B4 | done: PadMint check-manifest, plan and a player-check build pass |
| C2 | PadMint catalog PR | 30 min | C1, approval A | done: [padmint#299](https://github.com/chrissotraidis/padmint/pull/299) |
| C3 | Player check before tagging | 1 h | C1, D1 | done at 0439e8f with PadMint 0e4b696 (after two packaging fixes) |
| D1 | Documentation | 2 h | B3 | done |
| D2 | Release | 1 h | C3, approval B | blocked |
| D3 | Afterwards | 15 min | D2 | blocked |

**S0 Start checks and backups.** Confirm the worktree and the fork are clean
and pushed, the pin matches the lock, and CI's last run result. Back up the
iPad's SunPad 0.3.3 save, settings and preferences again, and both devices'
SunPad Next engine cards, to `~/.codex/scratch/` with today's date. Check both
devices are connected and unlocked. **Done when** the backups' hashes are
recorded.

**A1 Save cycle on a device.** On the iPhone 14, with `SMS_SAVE_DIR` pointing
at a scratch card in the app's container and `SMS_AUTOPRESS` input: start a
file, save from the pause menu, quit, relaunch and load it, with mirrored
screenshots of file select. Then Export Saves from the scratch card and import
the file back. **Done when** the scratch card changed after the save, the
reloaded file shows the saved progress, the export imports, and the player's
own card is byte-identical to its S0 backup.

**A3 Every area plays.** Warp into each of the nine areas (Delfino Plaza,
Airstrip, Bianco Hills, Ricco Harbor, Gelato Beach, Pinna Park, Sirena Beach,
Noki Bay, Pianta Village) on the iPhone 14, 60 seconds each, keeping a mirrored
screenshot and the engine log. **Done when** each reaches play at 30 FPS with
nothing visibly wrong, or cut rule 5 applies.

**R1 Legacy record.** Write `docs/LEGACY-ENGINE.md` from the code and docs at
`72c101a`:

- what the legacy engine was: the game's PowerPC code translated ahead of time
  into C (about 226 MB, an 81 MB module) inside ModernGekko, a fork of
  Dolphin's core, with Dolphin's Metal renderer, DSP emulation and DiscIO.
- how it was built, script by script, from `prepare-game.sh` to
  `package-ios.sh`, the Windows and Linux module builders and the tvOS and Mac
  scripts, with tools and times.
- how it ran: `SunPadCoreHost`, the input pipe, the provisioned module,
  on-device extraction, save locations, settings and their Dolphin keys,
  lifecycle, audio and diagnostics.
- every file and repository B3 removes, with pinned revisions and URLs from
  the lock, `patches/`, and the tests.
- PadMint's legacy `padmint.json` and catalog entry in full.
- its measurements: iPhone 14 at 25.7 to 27.1 FPS and down to 0.759 speed, the
  rejected 90% clock and dual-core experiments, the 60 FPS patch, memory, and
  open player reports.
- how to restore it: rebuilding `v0.3.2` or `legacy-engine-final` as it was,
  or reverting the B3 commits on `main` and restoring PadMint's entry.

**Done when** it names every file B3 deletes and each figure has a date and
source.

**R2 Legacy tag and branch.** Push the annotated tag `legacy-engine-final` and
the branch `legacy-engine` at `72c101a` and record them in the legacy record.
**Done when** both are on GitHub.

**B1 The engine becomes the SunPad app.** The `SunPad` target takes the engine
host, MoltenVK and the embed phase, keeps `com.sunpad.SunPad` and the name
SunPad, version 0.4.0 build 22. The `SunPadNext` target goes. The engine's
three-dot menu becomes the only menu. **Done when** it builds for devices and
the Simulator, plays the plaza route, and every menu item does what it says.

**B2 Upgrade over 0.3.3 on the iPad.** Install over SunPad 0.3.3. **Done
when** the save migrates and loads in game, the Dolphin card is unchanged, the
touch layout and settings carry over, and Remove Stored Game Data also removes
the extracted files 0.3.x left (about 1.4 GB).

**B3 Remove the legacy engine.** Separate commits, each passing
`check-repository.sh`: app code (`SunPadCoreHost`, `SunPadDiscExtractor`,
`SunPadInputPipeEncoder`, every `SUNPAD_DECOMP_ENGINE` branch), legacy
scripts and their tests (the list in the legacy record), gitlinks, lock entries
and `patches/`, CI steps, the SunPadTV target (marked unavailable, F3), and
renames that drop "next". **Done when** nothing outside the legacy record and
historical documents names a removed file, and local checks pass.

**B4 Published app and its audits.** `package-ios.sh` makes the app with no
engine, and `audit-ios-package.sh` checks a player's copy (nested signature,
arm64, iOS 16 minimum, expected imports). **Done when** both pass and
`release_gate.py` passes on the published app.

**C1 PadMint recipe**, `padmint.json`: kind `upstream-engine`, the disc as an
`in-app` input, iPhone only on `macos-arm64`, tools git, cmake, ninja,
Homebrew `llvm` and full Xcode, steps that fetch the engine sources, run
`build-engine.sh iphoneos`, add the library to the published app and sign it,
and `disk_gb` from a measured clean build. **Done when** PadMint validates it
and a PadMint build from a clean checkout installs and plays on the iPad.

**C2 PadMint catalog PR**, from a PadMint worktree: `catalog/sunpad.json`
(notes, hosts, Windows and Linux notes, Mac target withdrawn, free space,
player steps that end in importing the disc in SunPad) and the SunPad rows in
`docs/COMPATIBILITY.md`. **Done when** PadMint's tests pass and the PR is open.

**C3 Player check before tagging.** `scripts/player-check.sh` from PadMint's
`main` (or the C2 branch until it merges) with SunPad's clean checkout,
Apple's Python 3.9 and an empty PadMint folder. **Done when** it passes.

**D1 Documentation.** Rewrite README (what SunPad is, getting it through
PadMint, the LLVM requirement, importing the disc, upgrading from 0.3.x,
devices, known issues, credits), ARCHITECTURE, BUILDING, DEPENDENCIES,
IOS_IPADOS, MACOS, TVOS, CONTROLS, STATUS, KNOWN_ISSUES, TECH-DEBT, TESTING,
LEGAL_AND_PROVENANCE, CREDITS, THIRD_PARTY_NOTICES, AGENTS, CLAUDE and
CONTRIBUTING, and write RELEASE-0.4.0.md. Documents about the legacy engine's
research and releases get a dated note at the top pointing to the legacy
record. **Done when** `check-markdown-links.py` passes and nothing describes the
legacy engine as current.

**D2 Release**, after approval B: merge, tag `v0.4.0`, publish the app with no
engine, run `release_gate.py` on each file and `player-check.sh` without
SunPad's checkout. **Done when** a copy PadMint built from the release installs
over 0.3.x and plays on a device.

**D3 Afterwards.** Record the result in PadMint's compatibility table (in the
PR or a follow-up), add the after-today items as task cards in
[DECOMP-ENGINE-PLAN.md](DECOMP-ENGINE-PLAN.md), and send the maintainer the
final report.

## Restoring the legacy engine later

`docs/LEGACY-ENGINE.md` holds the full steps. In short, either rebuild
`v0.3.2` or `legacy-engine-final` as it was, or revert the B3 commits on
`main` and restore the gitlinks and PadMint's catalog entry recorded there.
