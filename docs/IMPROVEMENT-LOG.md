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

### 2026-10-07 plan: agent entry points
Result: done
Pins: unchanged
Checkpoints: documentation only
Evidence: AGENTS.md, CLAUDE.md, plan "Start here" section
Notes: AGENTS.md now points agents to the plan; CLAUDE.md imports AGENTS.md so
  Claude-based agents get the same instructions. The status table marks what
  each task needs (source only, disc image, or a human). Releases stay paused.
Next: task 1.1 and task 2.1 (independent).
