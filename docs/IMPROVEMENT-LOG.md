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
