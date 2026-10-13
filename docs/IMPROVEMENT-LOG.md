# Improvement run log

Append-only record for the [improvement plan](IMPROVEMENT-PLAN.md). Add the
newest entry at the bottom. Never edit an old entry; correct it with a new one.

## Entry template

```text
### YYYY-MM-DD task <id>: <title>
Result: done | reverted | skipped | rejected | blocked
Pins: SunPad <sha>, ModernGekko <sha>, RecompCore <sha>, DolRecomp <sha>
Checkpoints: C1 pass/fail (detail); C2 <baseline> -> <candidate>, noise <x>%;
  C3 <device, route, median/worst speedRatio before -> after>; C4 <sizes, times>;
  C5 <who, scenes, verdict>
Evidence: <log or artifact paths outside Git, PR links>
Notes: <what was learned; why kept, reverted or stopped>
Next: <the next task or the question for a human>
```

## Measurements

Record each pin set's noise floor and the pass 2 ranking table here when they
exist.

**2026-10-10, desktop Noki Bay, Mac (provisional).** Pins ModernGekko aa0f3f7,
RecompCore 39b9b98, DolRecomp fa0cf61. Route: warp to Noki Bay episode 1, Mario
idle, limiter off. The Mac was shared with other
jobs (load average 20-200, GPU 25-35% busy before SunPad started), so speed
varied about 20% between identical runs and no noise floor is recorded. Shares
are of the CPU-GPU thread from one 25 s `sample` capture taken before the
benchmark set the idle PC; the A/B runs below set 0x80348814 as iOS does:

| Cost | Share | Notes |
| --- | --- | --- |
| EFB copy readback wait (`StagingTexture::Flush`) | 13.6% | 11 copies per frame, all deferred; counters put the wait at 20-23% of wall time |
| Translated game code | ~60% total | no 16 KiB chunk above 3.5% self time; hottest are GX library chunks |
| Performance query wait (sun flare) | 2.1% | `Metal::PerfQuery::FlushResults` |
| EFB colour peek wait | 1.3% | `FramebufferManager::PeekEFBColor` |
| MMIO write hook (gather pipe) | 1.4% inclusive | below the 3% gate |
| Unmodeled-instruction fallback | 0.2% inclusive | below the 3% gate |
| Guest idle loop (`SelectThread+0x138`) | 8.9% | only without the idle PC; iOS sets it, and the loop exits to the idle skip every 256 cycles |

Upper-bound check for the readback wait: `EFBToTextureEnable = True` (no RAM
writeback) removed the wait but not the time. Medians: writeback on 1.064 and
0.845, off 0.840 and 0.869; later pairs were lost to a load spike. It also adds
a doubled reflection of the central platform in the goop water, so it is not a
usable setting. On this Mac the wait tracks GPU completion latency, and the
thread waits elsewhere when it is removed. Whether it is removable cost on the
iPhone 14 needs the device ranking (task 2.6).

## Ideas

Unmeasured ideas. Promote one to a task card only through the plan's
[candidate intake](IMPROVEMENT-PLAN.md#adding-new-work).

- Metal binary archives for known pipelines (from the performance research).
- Hot-region LLVM objects for measured chunks (from the performance research).
- Per-stage pipeline warmup during loads, from a recorded list of each stage's
  pipelines (research pass 1; sms-pc-port compiles 849 programs over 41 stages
  this way). Needs a first-moments hitch measurement on iPhone first.
- Audio after slow frames: check whether SunPad's audio path replays or drops
  blocks during sustained slowdowns, and whether a queue that grows after an
  underrun helps (research pass 1; see AUDIO_ISSUE.md).
- Heat-wave bypass that does not change code bytes, so it costs no chunk and
  can become its own setting (research pass 1).
- Button prompts that match the connected controller, using custom textures
  with original artwork (research pass 1; needs task 7.1).
- In-app "What's new" when releases resume (research pass 1).

## Entries

### 2026-10-07 plan: created
Result: done
Pins: SunPad c77dd61, ModernGekko 8f49c55, RecompCore da96175, DolRecomp fa0cf61
Checkpoints: documentation only
Evidence: [sms-pc-port review](SMS-PC-PORT-REVIEW.md)
Notes: Symbol map hash matches the extracted main.dol. The pinned DolRecomp
  already inlines the FP-enabled check and has an opt-in direct-call path that
  is off. ModernGekko supports code mods, but SunPad does not set
  mod_directories. Dolphin's GCI folder writes saves in place.
Next: task 1.1 and task 2.1 (independent).

### 2026-10-07 plan: agent entry points
Result: done
Pins: unchanged
Checkpoints: documentation only
Evidence: AGENTS.md, CLAUDE.md, plan "Start here" section
Notes: AGENTS.md now points agents to the plan; CLAUDE.md imports AGENTS.md so
  Claude-based agents get the same instructions. The status table marks what
  each task needs (source only, disc image, or a human). Releases stay paused.
Next: task 1.1 and task 2.1 (independent).

### 2026-10-10 task 2.1: symbol map fetch and verify
Result: done
Pins: SunPad eeaa38d (base), ModernGekko aa0f3f7, RecompCore 39b9b98, DolRecomp fa0cf61
Checkpoints: C1 fixture test (tests/test-profile-tools.sh) pass; real run wrote
  12,903 functions after both hash checks passed
Evidence: scripts/fetch-gmse01-symbols.sh; map in the ignored game build folder
Notes: Refuses a symbols.txt SHA-256 mismatch and a main.dol SHA-1 mismatch
  before writing anything.
Next: task 2.2.

### 2026-10-10 task 2.2: profile symbolizer
Result: done
Pins: as above
Checkpoints: C1 fixture test pass
Evidence: scripts/symbolize-profile.py
Notes: Reads macOS `sample` output, which needs no Instruments export. Module
  symbols are chunk-level (`func_<addr>` covers 16 KiB), so chunks are labelled
  with the game functions they cover and `loop_<addr>` becomes function+offset.
  `--callers SYMBOL` lists the paths into a symbol, which is how the readback
  wait was traced. Exact hottest-function attribution needs guest PCs, which
  sampling cannot see.
Next: tasks 2.4 and 2.5.

### 2026-10-10 tasks 2.3-2.5: warp, perf log, benchmark (partial)
Result: blocked (desktop noise floor; device ranking needs a human session)
Pins: as above
Checkpoints: C1 not run (lockstep); runtime changes are opt-in and default-off.
  Desktop runs above. No device run.
Evidence: ModernGekko aa0f3f7 (warp, perf log), RecompCore 39b9b98 (EFB copy
  counters), scripts/bench-route.sh
Notes: The warp is a runtime env var rather than a mod or launch argument: mod
  hooks restore CPU state after they run, and a one-shot write needs no dispatch
  change. It rewrites TApplication.mNextArea once during the opening movie, so
  the game's own loader enters the area; confirmed by screenshot in Noki Bay with
  no input or save. Boot to gameplay took 105-170 s on the loaded Mac because the
  opening movie plays in full. Only the `noki` route exists; it is an idle route,
  not traversal. Task 2.3 has EFB copy counters only, attributed by sync point
  (draw done, token, interrupt token, frame end); the other breakdown fields
  remain.
Next: (human) one iPhone 14 session: install a build with these pins, launch
  with MODERNGEKKO_DEV_WARP=9,0 MODERNGEKKO_PERF_LOG=10 for 15 minutes, and pull
  the console log, giving the device readback share and its sync point. Then
  re-measure the desktop noise floor on a quiet Mac and add the plaza and
  effects routes.

### 2026-10-11 research pass 1: SMS Launcher and sms-pc-port
Result: done
Pins: SunPad eeaa38d; read SMS Launcher b460678 (v0.1.57), sms-pc-port
  a8669e0, decompilation 967436b
Checkpoints: documentation only
Evidence: [research loop](RESEARCH-LOOP.md), with the inventory and source rules
Notes: SMS Launcher is MIT; sms-pc-port still has no license and still needs
  Rosetta 2 on Apple silicon, so the review's conclusions stand. Players get
  more there on PCs: 60/120 FPS, HD textures, graphics options, save import and
  backups, rumble, camera options. SunPad already has widescreen, render
  scale, an FPS counter, button and touch remapping, and a shareable diagnostic
  report. Saves sit in Library/Application Support, out of reach of Files.
  Promoted 10.1 save import and export, 10.2 iPhone and iPad rumble, 10.3
  invert camera up/down. Added findings to 7.1 and 8.1 and five ideas.
Next: tasks 10.1-10.3 can start now alongside 1.1 and 2.1.

### 2026-10-11 task 10.1: save import and export
Result: in progress (code landed; C5 pending)
Pins: SunPad 48f420a, ModernGekko 8f49c55, RecompCore da96175, DolRecomp fa0cf61
Checkpoints: C1 pass (new save transfer regression with synthetic saves;
  changed iOS sources type-check against the iOS Simulator SDK;
  check-repository.sh); C5 pending
Evidence: this PR
Notes: Rules come from RecompCore's GCMemcardDirectory and GCIFile: Dolphin
  loads every .gci with the current game code, refuses a second save with the
  same maker, game code and internal filename, and requires 64 bytes plus
  8 KiB per block. SunPad's user folder makes the card
  Application Support/SunPad/GC/USA/Card A. Imports are staged and applied in
  startGameIfProvisioned before the core starts, after a full card backup.
  Backups go to Documents/Save Backups (Files-visible), a change from the task
  card, so players can restore them. Apple TV is unchanged.
Next: human C5 on the iPad, following the device session protocol: export the
  current save and compare its hash with the card file; import a Dolphin GMSE01
  .gci, reopen, confirm it loads in game, then save and export again and load
  the export in Dolphin; confirm the backup folder holds the previous save.

### 2026-10-11 task 10.3: invert camera up and down
Result: in progress (code landed; C5 pending)
Pins: SunPad 48f420a, ModernGekko 8f49c55, RecompCore da96175, DolRecomp fa0cf61
Checkpoints: C1 pass (input pipe encoder regression covers vertical inversion
  alone and with the horizontal option, and checks the main stick is
  unchanged; check-repository.sh); C5 pending
Evidence: this PR
Notes: New "Invert C-stick Up/Down" switch in Touch Control Settings, beside
  "Modern C-stick L/R", off by default, saved as SunPadInvertCStickVertical and
  applied in SunPadInputPipeEncoder, so touch and controllers match. It applies
  at once, like the horizontal option. Apple TV has no switch for either axis
  and is unchanged.
Next: human C5 on the iPad: turn the switch on and off with a controller and
  with touch, and confirm only camera up/down reverses.

### 2026-10-11 task 10.2: controller rumble on iPhone and iPad
Result: in progress (code landed; C5 pending)
Pins: SunPad 48f420a (base), ModernGekko 9fec016, RecompCore 8579284, DolRecomp fa0cf61
Checkpoints: C1 pass (controller rumble regression and wiring checks; changed
  iOS sources type-check against the iOS Simulator SDK; RecompCore GCPad.cpp
  type-checks for iOS Simulator and macOS; check-repository.sh); C5 pending
Evidence: chrissotraidis/RecompCore#24, chrissotraidis/ModernGekko#2, this PR
Notes: The game's motor commands reach Pad::Rumble through the standard
  controller device, but SunPad's pipe input has no outputs. RecompCore now
  calls a weakly imported SunPadSetRumble for pad 0 on iOS and iPadOS only,
  as the tvOS lane already does with SunPadTVSetRumble. The app's
  SunPadControllerRumble follows player one from controller reconciliation,
  starts the Core Haptics engine before creating its player, and rebuilds the
  engine after iOS stops or resets it. The emulation thread only reads atomic
  flags. Controls → Controller Rumble is off by default. The Apple TV app keeps
  its own rumble code; adopting the shared class there is a follow-up.
Next: human C5 on the iPad with a haptics controller (DualSense or Xbox):
  turn rumble on, take damage and ground-pound, background and return, and
  turn it off mid-rumble; confirm rumble starts and stops with the game.

### 2026-10-11 tasks 1.1-1.3: save fault test, atomic writes, backup and repair
Result: 1.1 and 1.2 done; 1.3 in progress (desktop save and reload pending)
Pins: ModernGekko fa822d4, RecompCore eaa21f0, DolRecomp fa0cf61
Checkpoints: C1 pass (RecompCore unit suite, 1,037 tests on an arm64 Mac,
  including six new GCMemcardDirectoryTest cases; check-repository.sh)
Evidence: chrissotraidis/RecompCore#25, chrissotraidis/ModernGekko#3, this PR
Notes: The GCI write moved into Memcard::WriteGCIFile with a test-only
  stop_after_blocks option. The fault test stops a second write after each
  block and reloads the folder through GCMemcardDirectory. On the in-place
  write it failed for the right reason (every interrupted write left no save).
  Fix: write <file>.tmp, flush, File::RenameSync over the save. Before the
  rename a complete current save is copied to <file>.bak; at load a short
  .gci with a complete .bak moves to <file>.damaged and is restored, with one
  warning "GCI restored from backup: <name>". A damaged file is never kept as
  the backup, and a leftover .tmp is removed after its save loads. The header
  write is still compiled out (_WRITE_MC_HEADER), so 1.2's header part is
  unchanged. SunPad's save export ignores .bak, .tmp and .damaged files.
Next: 1.3 needs a desktop save and reload with the game; then task 1.4's
  device session (terminate during the flush window, relaunch, confirm the
  save loads), after which known issue 22 can be marked fixed.

### 2026-10-13 issue follow-up: metadata and release-status reconciliation
Result: done (documentation and directory metadata; device gates unchanged)
Pins: SunPad e57ebb5 (base); dependency pins unchanged
Checkpoints: check-repository.sh pass; .recomp.json validates against a locally
  downloaded recomp.board v1 schema; git diff --check pass
Evidence: issue #70; published v0.2.1 package readback; issue #54, #23 and #12
  follow-up comments
Notes: Added public descriptive metadata without a remote schema reference or
  build integration. Corrected stale startup/release wording: v0.2.1 was
  separately approved and published on 4 October; further releases still need
  clearance. The package checksum, ZIP integrity and scene manifest were
  checked; no physical iOS 27 or reporter acceptance is implied.
Next: refresh draft #57 against main and complete available host checks;
  prepare task 2.6's device measurement without claiming a speedup.

### 2026-10-13 task 2.6: iPhone baseline preflight
Result: blocked (device data preservation and human session)
Pins: SunPad a0db9c0 main; installed iPhone app 0.2.0 / build 14
Checkpoints: no new C3 or C5 acceptance
Evidence: private device-query and app-data-copy logs; issue #12 follow-up
Notes: The connected iPhone 14's app version and preferences could be read,
  but complete Documents and Library copies timed out. The partial backup and
  recovered save hash are retained privately; they do not establish a complete
  backup. No app was replaced, reset or uninstalled. The installed version
  predates the current profiling work. The remaining route work in 2.3-2.5,
  a current instrumented app, and a human device session are still needed.
Next: with the iPhone connected and unlocked, complete both app-data copies
  and verify save hashes before any in-place install with the same signing
  identity. Then run the recorded Noki protocol with a person checking
  gameplay/audio and thermal conditions, and finish the plaza/effects routes
  before claiming the full 2.6 ranking. Passes 3-6 remain gated on measurements.

### 2026-10-13 draft #57: refresh the personal iPhone module recipe
Result: in progress (Linux and physical-device acceptance pending)
Pins: SunPad 5a3432d build inputs, then merged a0db9c0 documentation;
  dependency pins unchanged from main
Checkpoints: check-repository.sh pass; clean iOS and tvOS CI pass at 5a3432d;
  PadMint manifest and per-host requirement checks pass
Evidence: SunPad #57; PadMint #152 (merged, all ten CI checks pass)
Notes: Refreshed the draft against current main and limited Xcode/xcrun
  requirements to Mac hosts. A fresh Mac check exposed missing tool setup and
  base-app forwarding in the shared player-check helper; PadMint #152 fixes
  both, with five focused fixtures and 333 passing tests on Apple's Python.
  The private Mac game-build result and exact revision are recorded in #57.
  Docker's daemon was unresponsive during bounded checks, preventing refreshed
  Linux ARM64/x86-64 proof. Historical Linux evidence remains labelled as such.
Next: complete the host-build and safe device gates listed in #57 before
  leaving draft. No new release or performance improvement is claimed.


### 2026-10-13 draft #57: refreshed Mac and Linux host proof
Result: host builds and package checks pass; physical Linux-module check pending
Pins: SunPad 81a66cb; PadMint main 7758cf4; published v0.2.1 base app
Checkpoints: source suite and clean iOS/tvOS CI pass at 81a66cb; fresh Mac
  player-check exits 0 using Apple Python 3.9.6, a fresh source checkout and
  an empty PadMint folder; updated Linux ARM64 and x86-64 builds exit 0
Evidence: #57; private build records, artifact readbacks and host inventories
Notes: The Mac personal IPA has SHA-256
  8eacbf71a403ad2843a85ba85101abab83ca82f4e8910d37fcbdeefca3ffedd0.
  Both Linux hosts produce the identical personal IPA with SHA-256
  0d74389bb27aea7ab654f85d6d28aad30ee4dfe920c6d3e10e6b20c2422a205c.
  Independent ZIP readbacks preserve all 2,797 base-app entries and add exactly
  one arm64 iOS module, minimum OS 16.0; import checks find zero app imports
  and three device C/C++ imports. All 225 generated files match across hosts.
  Linux uses Ubuntu 24.04 containers and LLVM 21.1.8; x86-64 runs under emulation
  on Apple silicon, so timings are not native-host performance results. ARM64
  was interrupted after native preparation to raise module jobs from two to
  six, then rerun with unchanged source/flags; the SDK refresh recompiled its
  module. Preserve the initial exit-130 record, and do not call that rerun an
  uninterrupted empty-cache build. x86-64 completed one uninterrupted build
  with separate native caches. All generated artifacts remain personal-only.
Next: after the maintainer's pending check of the installed Mac-built candidate,
  refresh the verified backup and test a Linux-built module on a physical
  iPhone/iPad before taking #57 out of draft. No new release is authorized.

### 2026-10-13 device preservation and deferred human checks
Result: complete backup and in-place candidate install verified; C3/C5 pending
Pins: published v0.2.1 / build 15 app with the Mac-built #57 module;
  current-source app at 81a66cb built and signed separately, not installed
Checkpoints: independently verified every regular file in Documents/Library;
  strict signature verification; post-install save/preferences hashes match;
  post-launch save hash matches; additional offline backup readback passes
Evidence: private USB inventory, per-file hashes, install and startup records
Notes: CoreDevice copies kept timing out. USB AFC/House Arrest recovered and
  verified 423 regular files (2,866,715,917 bytes). A recursive copy exited
  successfully after stopping at the runtime pipe; independent traversal
  caught the omission. Only that confirmed nonpersistent FIFO was excluded.
  The candidate was installed without uninstall/reset, using the existing
  signing identity and application entitlements. Its opening scene rendered.
  QuickTime's preview caused an audio interruption; after closing the preview
  and relaunching, short startup logs showed normal speed and no interruption.
  This is not hands-on sound/gameplay or a controlled Noki measurement. The
  maintainer deferred the save/controls/audio check. The installed candidate
  remains unchanged; the newer app for save/controller/profile work is staged.
Next: maintainer checks that the installed candidate loads the existing save
  and that movement, camera and sound work normally. Then refresh the backup
  before the current-source install and the 1.4/10.1-10.3 human checks. Complete
  the Noki/plaza/effects routes before the 2.6 ranking; passes 3-6 remain gated.

### 2026-10-13 task 1.3 preflight: packaged Mac resource lookup
Result: startup resource defect fixed; actual save and reload still pending
Pins: SunPad 4b953bd build inputs; ModernGekko e29496f; RecompCore 7240549;
  DolRecomp fa0cf61; tvOS lane unchanged
Checkpoints: C1 pass (source suite; real Common-library CLI and app-bundle
  lookup tests, with the bundle case failing before the fix; a symlink case
  also exposed and guards a path-resolution error. All three tests pass;
  relocated paths with spaces also pass); clean Mac app build pass;
  strict deep signature, portable linkage and macOS 14 load-command checks pass
Evidence: RecompCore #35, ModernGekko #4, SunPad #72; private build/startup logs
Notes: Local macOS builds looked for Sys at the app root while SunPad packages
  it beside the executable. The fork fix resolves the actual executable path
  on desktop macOS only, resolving symlinks before locating Sys. A clean SDK 27 package build also exposed the missing
  HAVE_PIPE2=OFF flag already used by preparation/mobile scripts; the packager
  now uses the same flag and an empty-directory rebuild succeeds. The packaged
  runner reports Contents/MacOS/Sys, loads the module without the missing-font
  error and shuts down normally. A copied save is unchanged. The initial
  private game probe reached the title/attract demo after a temporary resource
  workaround, but synthetic keyboard input did not establish save/reload
  acceptance. The later packaged-runner proof is log-based, not visual or
  gameplay acceptance. The installed iPhone candidate was not replaced.
Next: complete clean iOS/tvOS CI for this PR; with a person, perform the actual
  desktop save/reload check before marking 1.3 done, then the backed-up device
  session for 1.4. No new release or performance claim.

### 2026-10-13 draft #57: independent recipe review
Result: build boundaries rechecked; stale recipe note corrected
Pins: SunPad 50306de before the notes-only correction; build inputs unchanged
Checkpoints: current PadMint manifest validation and three-host command
  expansion pass, including paths with spaces; invalid jobs fail before tools
Evidence: #57; source review of the module script and metadata consumers
Notes: The recipe's descriptive note still named the superseded device build
  and packaging scripts. It now describes the module build and PadMint insertion
  that the recipe actually runs. The metadata remains descriptive JSON with
  no build or workflow consumer. This does not audit the external directory's
  service or establish device acceptance.
Next: retain the draft until the deferred candidate verdict and physical
  Linux-module check. The installed iPhone candidate remains unchanged.

### 2026-10-13 tasks 2.4-2.5: reject stalled and incomplete host probes
Result: two reproduced tooling defects fixed; measurement tasks remain open
Pins: SunPad main 1f2bc05 plus these script changes; runtime pins unchanged
Checkpoints: eight synthetic pipe/process regressions pass on Apple's Python
  3.9; bootstrap --sources-only and the complete source suite pass
Evidence: controller FIFO tests and benchmark runner fixtures in tests/
Notes: An existing FIFO without a reader previously blocked beyond the input
  tool's timeout. Connection now uses a nonblocking open and a bounded retry;
  connected command writes retain their existing behavior. A runner exiting
  during settling or after its first measurement previously could produce a
  successful benchmark row. The benchmark now rejects either early exit and
  records the exit status. Both failure cases were reproduced before fixing
  them. All fixtures use synthetic inputs; no game or device data is involved.
Next: complete the frame breakdown and timing fields, then the three repeated
  traversal routes. These tooling checks are not gameplay or speedup evidence;
  the maintainer's deferred iPhone candidate check remains the device gate.

### 2026-10-13 task 10.1: preserve saves when import cannot finish
Result: failed replacement preserves the active save; hands-on checks pending
Pins: SunPad main 1f2bc05 plus the app/helper changes; runtime pins unchanged
Checkpoints: synthetic filesystem-failure regressions and source suite pass;
  clean Apple CI remains required before merge
Evidence: SunPadSaveTransferTests; independent review of startup and retry paths
Notes: Import previously deleted matching saves before the final file move.
  An injected move failure reproduced the missing active save, although its
  dated backup survived. Import now completes the backup and atomically writes
  the replacement before deleting alternate copies. Enumeration, backup and
  commit failures preserve the original; mixed-case destination names are kept
  safely. Cleanup failures keep the import pending, and startup now waits for
  successful completion before opening the runtime. Otherwise, playing after
  such a failure could let the next retry replace newer progress. Pending-file
  removal errors are also reported. Tests use synthetic saves only.
Next: keep the installed iPhone candidate for the maintainer's deferred basic
  check. Before the later import/export session, refresh its backup and build
  the test app from current main; the previously staged app predates this fix.
  Confirm import, in-game save, export and reload on device before completing
  10.1. No new release or physical power-loss acceptance is claimed.

### 2026-10-13 task 10.1: refreshed internal device app
Result: app built and signed; staged only, installed candidate unchanged
Pins: SunPad 0373950 app source; unchanged runtime pins and personal module
Checkpoints: incremental device core build and fresh Release app build pass;
  strict deep signature and existing entitlement match pass
Evidence: private build logs, app/module hashes and staged-artifact record
Notes: The refreshed app contains the import failure guard. The device runtime
  reused the retained cache; this is not an empty-cache runtime build. The
  existing personal module is unchanged. No device launch or gameplay claim.
Next: after the deferred basic candidate check, refresh the device backup before
  any in-place install of this staged app and the save/controller checks.
