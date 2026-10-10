# SunPad improvement plan

- **Date:** 2026-10-07
- **Status:** planned work; nothing in this document is implemented yet
- **Baseline:** SunPad `c77dd61`; pins in [dependencies.lock.json](../config/dependencies.lock.json)
  (ModernGekko `8f49c55`, RecompCore `da96175`, DolRecomp `fa0cf61` on the Apple lane)
- **Research inputs:** [sms-pc-port review](SMS-PC-PORT-REVIEW.md),
  [Apple performance research](APPLE-PERFORMANCE-RESEARCH.md),
  [performance technical debt](TECH-DEBT.md)
- **Run log:** [IMPROVEMENT-LOG.md](IMPROVEMENT-LOG.md)

This plan makes SunPad faster on older hardware and safer with saves without
changing what it is: the retail Sunshine program, translated ahead of time, on
the Dolphin-derived runtime. It is written so an agent can pick up one task,
finish it, prove it, record it, and stop. Read the whole document once before
starting, beginning with [Start here](#start-here). After that, the
[goal loop](#the-goal-loop) is the procedure for every session.

## Start here

Use this plan when asked to continue the improvement plan, improve SunPad's
performance or save safety, or pick up SunPad engineering work without a more
specific request.

**First session:**

1. Read [AGENTS.md](../AGENTS.md), [CONTRIBUTING.md](../CONTRIBUTING.md), this
   plan, and the newest entries in [IMPROVEMENT-LOG.md](IMPROVEMENT-LOG.md).
2. Check access: `gh auth status`, and push rights to the forks you will touch,
   for example `gh api repos/chrissotraidis/RecompCore --jq .permissions.push`.
3. Check inputs. Ask the maintainer where the GMSE01 disc image and the primary
   checkout's prepared game workspace are. Without them, work only on tasks
   marked **S** in the [status table](#status).
4. Create a worktree from current `origin/main` ([environment](#environment)).
5. Run the [goal loop](#the-goal-loop) for one task.

**End of every session:**

- Append a log entry, even when the result is `blocked` or `reverted`.
- Update the status table in the same PR.
- Leave the repositories with no unpushed work. If a human step is next, write
  exactly what the human needs to do in the log entry's `Next:` line.

**Two tasks can start immediately:** 1.1 (save fault test, RecompCore) and 2.1
(symbol map script, SunPad). They do not depend on each other.

**Releases are paused.** [AGENTS.md](../AGENTS.md) forbids publishing or
restoring any release, IPA or download link until the maintainer's release
audit clears this repository. "Candidate build" in this plan means an internal
build for testing only.

## Goals

1. **Never lose a save.** A crash or iOS termination during a save leaves the
   previous save or the new one intact.
2. **Hold original 30 FPS on iPhone 14 class hardware (A15).** The worst
   measured iPhone 14 interval ran at 0.759 speed with the game thread
   saturated, so the critical path needs about 24% less work (about 32% more
   throughput). Older chips are measured after this goal is met; nothing is
   promised for them yet.
3. **Know where every frame goes** on device, by subsystem and by named game
   function, from a repeatable route.
4. **Then add features** the extra headroom pays for: HD texture packs, a real
   60 FPS mode for Macs and M-series iPads, and widescreen polish.

When goal 2 is met, stop optimizing. Do not keep shaving time once the target
holds; move to goal 4 or to measured defects.

## Words used in this plan

| Term | Meaning |
| --- | --- |
| Module | `gGMSE01_recomp.dylib`, the game code DolRecomp translated to ARM64. Generated locally from the user's disc; never committed. |
| Chunk | A 16 KiB slice of the module. The runtime hashes each chunk's original bytes and runs it natively only while guest memory still matches. |
| SMC demotion | A chunk whose bytes changed (Gecko code, heat-haze patch) is sent to the interpreter. Correct but slow. |
| Chassis | RecompCore's StaticRecomp core that dispatches into the module, validates chunks and runs hooks and mods. |
| Lockstep | `STATICRECOMP_LOCKSTEP=1`: the runtime re-runs native blocks on the interpreter and reports any difference. The correctness oracle for compiler and replacement work. |
| Route | A fixed, scripted piece of play used for every measurement. Defined in task 2.5. |
| A/B pair | One baseline run and one candidate run, back to back, same route and settings. |
| Speed ratio | `speedRatio` in SunPad's ten-second `performance` log line: emulated time over wall time. 1.0 is full speed. |
| Mod | A ModernGekko code mod (`*.mgm`) that patches or hooks a guest function by address. See `mod-template/README.md` in ModernGekko. |

## Ground rules

- **No sms-pc-port code.** It has no license. Use its documented findings and
  re-derive behavior from the CC0 decompilation, Dolphin and SunPad's own
  measurements. Cite the port where a finding came from.
- **Retail behavior is the reference.** Every native replacement and code
  generation change must match the generated original or the interpreter bit
  for bit, including CPU state the caller can observe. No fast-math, no removed
  exception paths, no blessed SMC hashes.
- **Owning forks.** Compiler changes go to DolRecomp, runtime changes to
  RecompCore or ModernGekko, app changes here. Update pins, gitlinks and the
  lock together ([CONTRIBUTING](../CONTRIBUTING.md)).
- **Evidence is separate.** Unit tests, desktop lockstep, Simulator, device
  telemetry and hands-on play are separate gates. A task is done only when its
  own gate passes.
- **Original 30 FPS stays the default.** New behavior ships default-off or
  behind a developer launch argument until its gate passes.
- **Protect player data.** Back up and read back saves and settings around every
  device install ([device session](#device-session-protocol)).
- **One change per measurement.** Never A/B two changes at once.

## The goal loop

Run this loop once per working session. Each session should finish one task
card or stop at a recorded checkpoint.

1. **Read state.** Open [IMPROVEMENT-LOG.md](IMPROVEMENT-LOG.md) and the
   [status table](#status). Pick the first task whose status is `ready` and
   whose prerequisites are `done`. If none is ready, go to step 9.
2. **Check the entry gate.** Every pass has a "worth trying" rule. If the
   measurement it needs is missing, do the measurement task first. If the rule
   fails, mark the pass `skipped` with the numbers and pick again.
3. **Prepare an isolated checkout.** Use a worktree under
   `~/.codex/worktrees` ([environment](#environment)). Never reset, clean or
   overwrite dirty trees under `ref/` in the primary checkout.
4. **Record the baseline** the task's gate compares against, unless the log
   already has one for the same pins, route and device.
5. **Make the smallest change that can pass the gate.** Follow the task card's
   steps. Add the card's tests before or with the change.
6. **Run the correctness checkpoints** ([C1](#hard-checkpoints)). Any failure:
   fix or revert. Do not measure performance on an incorrect build.
7. **Run the performance and cost checkpoints** that the card names (C2-C4).
   Then decide:
   - **Keep:** all named checkpoints pass.
   - **Revert:** a checkpoint fails and the cause is understood. Record why.
   - **Stop:** the task hit its timebox (twice its estimate) or failed the same
     gate twice. Mark it `rejected` or `blocked` with numbers and move on.
8. **Record and land.** Append a log entry, update the status table, open PRs in
   the owning repositories, and land them in dependency order
   ([landing changes](#landing-changes)).
9. **Re-plan when the queue is empty or a phase ends.** Re-run the pass 2 routes,
   re-rank costs, and add new task cards only through
   [candidate intake](#adding-new-work). If goal 2 is met, stop the speed work.

**Ask a human and wait** for: a physical-device session, any change to a
player-visible default, a release or published IPA, deleting or migrating user
data, a licensing question, or a checkpoint that fails twice with no clear
cause. Prepare everything first so the human only has to approve or run the
session.

## Hard checkpoints

Each task card lists which checkpoints apply. They are pass/fail, not advice.

**C1 Correctness (always).**

- The owning repository's unit tests pass; for SunPad,
  `./scripts/check-repository.sh` passes.
- Desktop lockstep on all three routes ends with `[lockstep] summary:` showing
  `reports=0`, and the log has no `[lockstep] DIVERGE` or
  `[lockstep] UNDERCHARGE` lines.
- `./scripts/audit-generated-gmse01.sh` passes on a regenerated module when the
  compiler changed.
- The count of failed or demoted chunks in the run is no higher than the
  baseline's for the same settings.
- Frame captures at the route's capture points match the baseline, except where
  the task intends a visual change.

**C2 Desktop performance (worth keeping on Mac).**

- Run the route with the frame limiter off (task 2.4) in five interleaved A/B
  pairs in the order A B B A A B B A A B.
- The **noise floor** is the median absolute difference between two baseline
  runs, measured once per pin set and recorded in the log.
- Pass when the median gain in average VPS (emulated frames per second) is at
  least 3% and at least twice the noise floor, and at least four of five pairs
  improve.

**C3 Device performance (worth shipping).**

- iPhone 14, same route, native 1x, Original 4:3, original 30 FPS, Low Power Mode
  off, not charging, no screen recording, 15 minutes.
- Compare the median and the worst ten-second `speedRatio`.
- Pass when the worst sample improves by at least 0.03 or reaches 0.98 or
  better, the median does not fall, and time to Serious thermal state is not
  more than 10% shorter.

**C4 Cost limits.**

- Module size grows by no more than 10%.
- Launch-to-first-frame time grows by no more than 10%.
- Resident memory on iPhone grows by no more than 50 MiB (texture packs excepted).
- Module build time grows by no more than 25%.

**C5 Hands-on.** For anything that can change what the player sees or feels, a
human plays the affected scenes and writes a verdict in the log. Telemetry
alone never passes C5.

**Entry gate ("worth trying").** A speed pass starts only if pass 2 shows its
target cost is at least 3% of game-thread time on the iPhone 14 route. Below
that, mark it `skipped` with the number.

## Environment

**Isolation.** Follow [AGENTS.md](../AGENTS.md): work in a worktree under
`~/.codex/worktrees`, not a new clone in the GitHub folder. The primary
checkout's `ref/` trees may be dirty or behind; do not reset or clean them.
For fork work, clone or worktree the fork under the task's scratch directory.

**Sources and game data.**

```sh
./scripts/bootstrap-dependencies.sh            # pinned forks plus Apple build externals
./scripts/prepare-game.sh /path/to/GMSE01.iso  # verifies the image, extracts, generates the module
./scripts/check-repository.sh                  # source suite
```

`prepare-game.sh` regenerates the module; the C compile takes about 15-25
minutes. Avoid regenerating for work that can be tested as a mod.

**Desktop runs.**

```sh
./scripts/stage1-run.sh                          # Metal desktop run, log in artifacts/runtime/
STATICRECOMP_LOCKSTEP=1 ./scripts/stage1-run.sh  # lockstep (slow)
python3 scripts/gcpipe.py --sequence route.json  # scripted input through the pipe device
```

Lockstep is slow. `STATICRECOMP_LOCKSTEP_START` and `STATICRECOMP_LOCKSTEP_LIMIT`
limit the checked window. `STATICRECOMP_DISPATCH_SAMPLES=1` collects dispatch
samples.

**Benchmarks and profiles.**

```sh
./scripts/fetch-gmse01-symbols.sh                 # verified function map (task 2.1)
./scripts/bench-route.sh noki <label>             # one CSV row in artifacts/bench/
sample <pid> 30 1 -file noki.sample.txt           # macOS sampler, while a route runs
python3 scripts/symbolize-profile.py noki.sample.txt \
  --map ref/ModernGekko-Template/build/symbols/GMSE01.map   # ranked self time
```

The runtime hooks behind these are off unless set:
`MODERNGEKKO_DEV_WARP=<stage>,<scenario>` boots straight into an area (Noki Bay is
`9,0`), `MODERNGEKKO_PERF_LOG=<seconds>` prints speed and EFB readback counters, and
`MODERNGEKKO_EFB_CENSUS=1` adds a per-copy census. They also work in the iOS app,
so a device run can be launched without anyone playing.

**iOS builds and install.**

```sh
./scripts/ios-build-core-device.sh               # device core and module
./scripts/deploy-ios-device.sh <device-id>       # in-place install, module copy, launch
```

Never use a removing CoreDevice copy for updates ([known issue 12](KNOWN_ISSUES.md)).

**CI.** Pull requests to SunPad `main` must pass `safety-and-tests`,
`apple-build (ios)` and `apple-build (tvos)`.

### Device session protocol

1. List the device: `xcrun devicectl list devices`.
2. Back up the app container before installing:

   ```sh
   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
     --domain-identifier com.sunpad.SunPad --source Documents --destination <backup>/Documents
   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
     --domain-identifier com.sunpad.SunPad --source Library --destination <backup>/Library
   ```

3. Record SHA-256 hashes of every save file in the backup.
4. Install in place with `deploy-ios-device.sh`.
5. Run the session. Copy the diagnostics log out of `Documents` the same way.
6. Read the saves back and compare hashes. Any unexpected difference stops the
   session.

### Landing changes

1. Fork change: branch `codex/<task-id>-<slug>` from the branch that contains the
   current pin (`git branch -r --contains <pin>`). Open a PR in the fork with the
   gate evidence. Merge when its checks pass.
2. Parent gitlinks: DolRecomp lives inside RecompCore (`DolRecomp`), RecompCore
   inside ModernGekko (`vendor/dolphin`), ModernGekko inside SunPad
   (`ref/ModernGekko`). Update each parent with the new full SHA, innermost
   first.
3. SunPad: update the gitlink, the matching entries in
   `config/dependencies.lock.json` and the table in
   [DEPENDENCIES](DEPENDENCIES.md#maintained-source-graph). Run
   `python3 scripts/dependency-lock.py` and `./scripts/check-repository.sh`.
4. The tvOS lane has its own pins. Change it only when the task says so.

## Status

Update this table in the same PR as the work. Status values: `ready`,
`in progress`, `done`, `skipped`, `rejected`, `blocked`.

Inputs: **S** needs only the source checkouts and a Mac toolchain; **D** also
needs the maintainer's GMSE01 disc image and a generated module; **H** needs a
human for a device session or a hands-on verdict.

| Task | Title | Status | Needs | Inputs |
| --- | --- | --- | --- | --- |
| 1.1 | Save fault-injection test | ready | none | S |
| 1.2 | Atomic GCI and header writes | ready | 1.1 | S |
| 1.3 | Last-good backup and load repair | ready | 1.2 | S |
| 1.4 | Pin and device save session | ready | 1.3 | D, H |
| 2.1 | Symbol map fetch and verify | done | none | S (fixture); D for the real hash check |
| 2.2 | Profile symbolizer | done | 2.1 | S |
| 2.3 | Frame breakdown counters | in progress | none | D |
| 2.4 | Unlimited-speed desktop benchmark | in progress | none | D |
| 2.5 | Developer warp and the three routes | in progress | 2.1 | D |
| 2.6 | Baseline measurement and ranking | ready | 2.2-2.5 | D, H |
| 3.1 | Chunk-validation flag for direct calls | ready | 2.6 entry gate | D |
| 3.2 | Hook and mod bitmap | ready | 3.1 | D |
| 3.3 | Enable safe direct calls | ready | 3.2 | D, H |
| 3.4 | Quantized load/store fast path | ready | 2.6 entry gate | D, H |
| 4.1 | Replacement harness | ready | 2.1, 2.6 entry gate | D |
| 4.2 | First replacement: top-ranked routine | ready | 4.1 | D |
| 4.3 | Remaining ranked routines | ready | 4.2 | D, H |
| 5.1 | Vertex format census | ready | 2.6 entry gate | D |
| 5.2 | Specialized loaders | ready | 5.1 | D, H |
| 6.1 | Readback settings A/B | ready | 2.6 entry gate | D |
| 6.2 | Deferred peek and pixel-metric answers | ready | 6.1 | D, H |
| 7.1 | HD texture packs | ready | goal 2 met or human approval | D, H |
| 8.1 | 60 FPS timing audit | ready | 4.1, headroom gate | S |
| 8.2 | 60 FPS mod | ready | 8.1 | D, H |
| 9.1 | Widescreen polish | ready | 8.2 or human approval | D, H |

## Pass 1: save durability

**Why.** `GCMemcardDirectory::FlushToFile` in RecompCore
(`Source/Core/Core/HW/GCMemcard/GCMemcardDirectory.cpp`) opens each dirty save
with `"wb"` and writes it in place; the card header is written the same way.
The loader skips any GCI whose size does not match its header, without a
message. A termination mid-write therefore hides the save. sms-pc-port hit the
same failure and fixed it with temp-file writes and load-time repair.

**Worth trying.** Always. This is a data-loss risk, not a speed change.

**Task 1.1: fault-injection test (1 day).** In RecompCore's unit tests
(`Source/UnitTests/Core/`), add a test that builds a GCI folder in a temporary
directory, writes a save, then simulates a stop after each block of a second
write (truncate the file at each block boundary). After each simulated stop, a
fresh `GCMemcardDirectory` must load either the old or the new save. The test
must fail on the current code. Done when it fails for the right reason.

**Task 1.2: atomic writes (1 day).** In `FlushToFile` and the header write,
write to `<file>.tmp`, flush, then replace the target with `File::RenameSync`
from `Common/FileUtil` (it renames and syncs). Keep the existing error
messages. Done when 1.1 passes and existing tests pass.

**Task 1.3: last-good backup and repair (1-2 days).**

1. Before replacing a save, rename the current file to `<file>.bak` (one
   generation; replace the previous `.bak`).
2. On load, before the size check skips a file: if the GCI is the wrong size
   and a `.bak` of the right size exists, move the bad file to
   `<file>.damaged` and load the `.bak`. If a `.tmp` exists, delete it only
   after the target loaded successfully.
3. Log one line: `GCI restored from backup: <name>`.
4. Extend 1.1 to cover a short file with and without a backup.

Done when tests pass and a manual desktop run still saves and reloads.

**Task 1.4: pin and device session (1 day plus a human session).** Land the
RecompCore change and pins ([landing changes](#landing-changes)). Prepare a
device session: make an in-game save, background the app and terminate it
from the Xcode or `devicectl` side during the flush window, relaunch, and
confirm the save loads. Gates: C1, the [device session
protocol](#device-session-protocol), and a log entry with save hashes. Then
update [known issue 22](KNOWN_ISSUES.md) as fixed.

**Stop if** `RenameSync` fails on iOS inside the app container. Record the
error and ask a human.

## Pass 2: measurement

**Why.** The August profiles predate the pinned toolchain, do not name game
functions, and cannot see time spent waiting on the GPU. Every later pass
depends on this data.

**Worth trying.** Always.

**Task 2.1: symbol map (1 day).** Add `scripts/fetch-gmse01-symbols.sh`:

1. Download `config/GMSE01/symbols.txt` and `config/GMSE01/build.sha1` from
   `https://github.com/chasem-dev/sms-english` at the commit recorded in
   [DEPENDENCIES](DEPENDENCIES.md#research-references-not-build-inputs)
   (`d5f4eb3...`).
2. Check `symbols.txt` against SHA-256
   `c75a8f35c1d51e7978cc66aeaa86c1d4e2d16c5603576183e0cd49e66a8d98ff`.
3. Check that `build.sha1` equals the SHA-1 of the extracted `main.dol`
   (`a6782903ef79d4196c8489ecb1b57decb5b3728f`). Refuse to continue otherwise.
4. Convert each line `name = .text:0xADDR; // type:function size:0xSIZE ...`
   to `ADDR SIZE name`, the format DolRecomp's `--map` parser accepts. Keep
   functions only.
5. Write the result under the ignored game workspace, never into Git.

Test with a small fixture file in `tests/` that contains made-up names.
Done when the script produces about 12,900 function lines and refuses a
mismatched hash.

**Task 2.2: profile symbolizer (1 day).** Add `scripts/symbolize-profile.py`. It
reads a text call tree exported from Instruments and the map from 2.1, and
replaces each `func_80XXXXXX` with `name+offset`. Generated chunk functions
cover many game functions, so also print the game function that contains the
hottest sampled guest PC when the input has PCs. Test with a fixture.

**Task 2.3: frame breakdown (4-5 days).** In RecompCore, accumulate time per
frame for:

| Field | Where to time it |
| --- | --- |
| `native` | StaticRecomp native dispatch (`StaticRecompCore_Run.cpp`) |
| `interp` | interpreter fallback steps in the same loop |
| `vertex` | vertex loading in `VideoCommon/VertexLoaderManager.cpp` |
| `peek` | `FramebufferManager::PeekEFBColor` and `PeekEFBDepth` |
| `pqwait` | `Metal::PerfQuery::FlushResults` |
| `copy` | EFB copy to RAM in the texture cache |
| `gpuwait` | `Metal::StateTracker::WaitForFlushedEncoders` and other waits |
| `shader` | pipeline compilation on the game thread |
| `present` | presentation and swap |

Expose the per-second sums through the ModernGekko runtime API and append them
to SunPad's ten-second `performance` log line as
`breakdown native=.. interp=.. vertex=.. peek=.. pqwait=.. copy=.. gpuwait=..
shader=.. present=..` in milliseconds per frame. Use a monotonic clock and add
no allocation or locking on the hot path. Gate: C1 and C2 show no slowdown
beyond the noise floor with counters on.

**Task 2.4: unlimited-speed desktop benchmark (2 days).** Add
`scripts/bench-route.sh <route> <label>`. It runs the desktop app with the frame
limiter off (Dolphin `[Core] EmulationSpeed = 0` in the runner's user
directory, or a runner flag if one exists), plays the route, and writes one CSV
row: label, pins, route, average VPS, p95 frame time, breakdown fields. Verify
first that the runner honors the setting: VPS must exceed 30 on the Mac.

**Task 2.5: warp and routes (4-5 days).**

1. **Warp.** `gpApplication` is at `0x803E9700` (symbol map). In the CC0
   decompilation's `include/System/Application.hpp`, `mNextArea` is a
   `TGameSequence` at offset `0x12`: stage (`u8`), scenario (`u8`),
   flag (`u16`). Dolphin's bundled `$Test Level` cheat writes this word.
   Add a developer-only launch argument `-sunpadWarp <stage>,<scenario>` that
   writes `mNextArea` once, when a saved file is loaded from file select, then
   stops writing. Implement it as a ModernGekko mod hook or a one-shot memory
   write; read the stage numbers from the decompilation and confirm each one
   with a screenshot. Never write it every frame.
2. **Routes.** Use a copied diagnostic save, never a player's save. Define three
   routes as `gcpipe.py` sequence files in `tests/routes/`:
   - `plaza`: Delfino Plaza traversal, 120 seconds;
   - `noki`: Noki Bay, the reported slowdown, 120 seconds;
   - `effects`: a water, goop and heat-haze scene, 120 seconds.
3. Each route records capture points (frame numbers) for C1 frame comparison.

Done when each route reaches the same place in five desktop runs.

**Task 2.6: baseline and ranking (1 day plus a human device session).**

1. Desktop: noise floor, then each route five times with `bench-route.sh`.
2. Device: each route on the iPhone 14 with the breakdown on, plus one
   Instruments Time Profiler capture per route, symbolized with 2.2.
3. Write a ranking table in the log: each cost's share of game-thread time per
   route. This table decides every entry gate below.

## Pass 3: safe direct calls and the quantized fast path

**Why.** By default the module returns to the chassis on every call between
chunks. Each round trip scans REL sections, looks up host-call hooks, runs mod
dispatch and flushes the cycle count. Pinned DolRecomp `fa0cf61` already
contains a direct-call path that calls the target chunk and resumes inline
(depth limit 24), but generation emits it only with
`DOLRECOMP_UNSAFE_DIRECT_CALLS=1`. It is off because a direct call skips the
chassis check that retires modified chunks. Separately, the emitter writes
`ppc_psq_load_inline`/`ppc_psq_store_inline` call sites, but in the pinned
sources those forward to the out-of-line helpers. DolRecomp's history records
about 4% from a real fast path in another title.

**Worth trying.** 3.1-3.3: dispatch plus address resolution is at least 3% of
game-thread time in the 2.6 ranking. 3.4: quantized load/store is at least 3%.

**Task 3.1: chunk-validation flag (3-4 days).**

1. RecompCore (`StaticRecompCore_SMC.cpp`) already tracks `m_chunk_state` per
   chunk. Export a read-only byte array, one byte per chunk, where 1 means
   `CHUNK_VERIFIED`. Update it everywhere chunk state changes.
2. Pass its address to the module through the ABI
   (`StaticRecompABI.h`). Bump `STATICRECOMP_ABI_VERSION` and reject
   mismatched modules, as the loader does today.
3. In DolRecomp `src/backend/emitter.c` (`emit_cross_chunk_call`), call
   directly only when the target chunk's byte is 1; otherwise take the existing
   return-to-chassis path. An unverified chunk then still goes through the
   chassis, which verifies it on first entry.

Tests: DolRecomp unit tests for verified, unverified and failed targets; a
RecompCore test that a modified chunk is never entered directly.

**Task 3.2: hook and mod bitmap (2 days).** At module load, mark every address
that has a host-call hook, a DolRecomp replacement or a ModernGekko mod patch
or hook in a bitmap the call site checks. Marked targets always go through the
chassis. Test with a mod that patches a function called across chunks.

**Task 3.3: enable (3-5 days).**

1. Replace the `DOLRECOMP_UNSAFE_DIRECT_CALLS` gate with a safe option that
   requires the 3.1 ABI, and keep an off switch for A/B builds.
2. Set it in SunPad's module generation (`prepare-game.sh` and the iOS module
   build).
3. Confirm that scheduled events (interrupts, timers, audio DMA) stay on time:
   run lockstep plus a 10-minute desktop audio comparison against the baseline.
   If events slip, flush the cycle count at the call site.
4. Confirm the 60 FPS Patch and widescreen modes still demote exactly their
   patched chunks.

Gates: C1, C2, C3, C4.

**Task 3.4: quantized fast path (3 days).** Provide real
`ppc_psq_load_inline`/`ppc_psq_store_inline` definitions in the module build:
handle the unquantized (GQR type 0) case with a MEM1 address directly and call
the existing helper for every other case. Differential test against the helper
on random GQR, address and value inputs. Gates: C1, C2, C3.

## Pass 4: exact native math

**Why.** Paired-single and FP helper emulation was the largest named cost in
several captures. Much of it sits in SDK and MSL routines the game calls
constantly. The symbol map gives their exact addresses, for example
`PSMTXConcat` at `0x803499F0`, `PSMTXMultVec` at `0x8034A2D0`,
`PSVECNormalize` at `0x8034A5D0`, `sinf` at `0x8033C7E4`,
`J3DPSMtxArrayConcat` at `0x802D3404`.

**Worth trying.** The 2.6 ranking shows the candidate routines together take at
least 3% of game-thread time. Replace routines in ranked order; stop when the
next one is below 0.5%.

**Where the code lives.** Write replacements as a SunPad ModernGekko mod
(`RECOMP_PATCH` at the routine's address). A mod rebuilds in seconds without
regenerating the module. SunPad does not set `mod_directories` today; task 4.1
adds that for desktop first. Before any iOS build, decide with a human whether
to ship the mod as a second signed dylib (packaging and audit changes) or move
the same source into DolRecomp's module-local `dolrecomp_dispatch_replacement`.

**Task 4.1: harness (4-5 days).**

1. Create `mods/sunpad-gmse01/` from ModernGekko's `mod-template`.
2. Add a desktop differential harness: for a routine, set up random guest inputs
   in emulated memory and registers, run the generated original, snapshot state,
   restore, run the replacement, and compare all memory written and all
   registers, including the paired-single halves, FPSCR and CR.
3. Cover random values plus NaN, infinity, denormals, zero, negative zero and
   aliasing (output equals input).
4. Charge the original's cycle count in the replacement so emulated timing does
   not change. Measure it with the harness and store it per routine.

**Task 4.2: first replacement (2-3 days).** Take the top-ranked routine. Write it
from the DOL's instructions and the CC0 decompilation. Follow Gekko rules: each
fused multiply-add rounds once; use the same `frsqrte`/`fres` estimate helpers
the generated code uses; round `fmuls` operand C to 25 bits; saturate
`fctiwz`. The sms-pc-port notes in the [review](SMS-PC-PORT-REVIEW.md) are a
checklist of these rules. If floating point is disabled or an address would
fault, call the original. Gates: one million harness inputs bit-exact, then C1,
C2.

**Task 4.3: remaining routines (half a day to a day each).** Repeat 4.2 in ranked
order. After every five routines, run C1, C2 and C4. Run C3 once at the end.

## Pass 5: specialized vertex loaders

**Why.** iOS cannot use Dolphin's runtime-generated ARM64 vertex loader, so it
uses the generic software loader, measured at up to 7.3% in one scene.
sms-pc-port's per-format readers more than halved its own vertex-loading time
without generating code at run time.

**Worth trying.** `vertex` is at least 3% of game-thread time on any route.

**Task 5.1: format census (2 days).** Log each distinct vertex-loader UID used
on the three routes, with call and vertex counts. Expect a small set. Commit the
census as a data file without game content.

**Task 5.2: specialized loaders (1-1.5 weeks).** For the formats that cover at
least 90% of vertices, add C++ template specializations selected by UID; use the
software loader for everything else. Byte-compare each specialization with the
software loader on recorded inputs, using Dolphin's vertex-loader test as the
pattern. Gates: C1, C2, C3.

## Pass 6: GPU readback waits

**Why.** Dolphin's `GMS.ini` enables EFB peeks, EFB copies to RAM and
performance queries for Sunshine. Each frame the game peeks 17 depths for the
sun flare and one colour for Mario's occlusion, reads goop pixel metrics, and
writes EFB copies back. In the Metal backend, performance-query reads and EFB
peeks that miss the tile cache block the single CPU-GPU thread until the GPU
finishes; EFB copies block when a deferred copy is needed early.

**Worth trying.** `peek + pqwait + copy + gpuwait` is at least 3% of frame time
on any route.

**Task 6.1: settings A/B (2 days).** One at a time: `EFBAccessTileSize`
(including 0, whole-EFB readback), `EFBAccessDeferInvalidation = True`, and
`DeferEFBCopies` (default on; confirm). For each, check the sun flare (look at
and away from the sun), goop cleaning progress and EFB-copy effects against the
baseline captures. Keep a setting only if it passes C1 and C2.

**Task 6.2: deferred answers (1-1.5 weeks).** If waits remain, add a
GMSE01-only mode in RecompCore that answers a group of peeks (peeks with no draw
between them) and each pixel-metric read from the previous frame's asynchronous
readback, reading synchronously only the first time a group appears. Gates: C1
with goop progress numbers identical to synchronous mode over the effects
route, C2, C3, C5.

## Pass 7: HD texture packs

**Why.** The pinned runtime contains Dolphin's custom-texture loader, and
community Sunshine packs use Dolphin's format. SunPad exposes no way to use them.

**Worth trying.** Goal 2 is met, or a human approves starting it earlier.

**Task 7.1 (1-1.5 weeks).** Add a default-off setting and a Files-visible
`Textures/GMS` folder. Keep prefetch off on iOS, log memory use, and turn
packs off after a memory warning. Size guidance for testing: the 1080p variant
of the community UHD pack (about 156 MB) on iPhone and iPad; the full UHD pack
(986 MB download) on Mac only until measured. SunPad never bundles or downloads
a pack. Gates: C1 with the setting off, C4 memory with it on, C5.

## Pass 8: real 60 FPS

**Why.** The current 60 FPS Patch is a six-line Gecko code. It demotes two
chunks to the interpreter and was judged unusable in hands-on play.
sms-pc-port needed 35 game-side timing fixes beyond reporting the higher rate,
which the Gecko code does not make.

**Worth trying.** On the target device at original 30 FPS, the game thread is
busy no more than 50% of the time (60 FPS roughly doubles the work). Target
Macs and M-series iPads first.

**Task 8.1: timing audit (1-1.5 weeks).** From the CC0 decompilation, list every
object that counts frames rather than time. Start from the port's list (wipes,
gates, console timers, flocks, grass and flag sway, rides, bosses, ripples,
smoke, particles, sound frame work) and search the decompilation for counters
compared against constants in `perform`/`control` methods. For each entry
record function, address, what it counts and how it must change at 60 FPS.

**Task 8.2: 60 FPS mod (3-4 weeks).** In the SunPad mod: report the active rate
from `SMSGetVSyncTimesPerSec`, keep movement on its 120 Hz ticks, and patch
each audited object. Disable the Gecko code in this mode so no chunk is demoted.
Keep it default-off and restart-required. Gate: the
[60 FPS support gate](TECH-DEBT.md#60-fps-support-gate), including C5 with a
written verdict per scene.

## Pass 9: widescreen polish

**Task 9.1 (1-2 weeks).** Use the port's checklist (camera aspect, full-width
fader, HUD panes kept 4:3 or anchored to edges) to fix SunPad's remaining 16:9
defects, as mod patches. Gates: C1 in 4:3, C5 in the reported 16:9 scenes.

## Schedule

Effort is focused engineering time for one agent or maintainer. It excludes
waiting for device sessions.

| Phase | Weeks | Tasks | Output |
| --- | --- | --- | --- |
| 1 | 1-3 | 1.1-1.4, 2.1-2.6 | Saves cannot be cut short; ranked, repeatable numbers |
| 2 | 4-10 | 3.x and 4.x; 6.x in parallel if its entry gate passes | Faster module and runtime |
| 3 | 11-13 | 5.x, full scene matrix on iPhone 14, iPhone 15 Pro and iPad | Internal candidate build with evidence (no public release while releases are paused) |
| 4 | 14-22 | 7.1, 8.x, 9.1 | Optional features on hardware with headroom |

Each phase ends with merged, pinned and documented work, so the plan can stop
after any phase.

## Success criteria for the speed work

- The three routes hold 0.98 speed or better at native 1x and original 30 FPS on
  the iPhone 14 for 15 minutes, including after the device reaches Serious
  thermal state.
- No lockstep reports, no new SMC demotions, and no visual, audio, physics,
  input, save or lifecycle regressions in the scene matrix.
- Module size and cold-start time are reported with the speed results.

If phases 2 and 3 finish without meeting this, re-rank with pass 2. Add work
only through candidate intake. If nothing measured is above 3%, record the
remaining gap and stop; the conservative CPU-clock option in the performance
research is the only remaining lever and needs human approval.

## Adding new work

A new task card needs one of:

- a measured cost of at least 3% of game-thread time on a route, with the log
  entry that shows it; or
- a reproduced player-visible defect with a log or capture.

Write it with the same parts as the cards above: why, worth-trying rule, steps,
tests, gates, estimate, stop rule. Add it to the status table. Ideas without
measurements go to the log's "ideas" list, not the table.

Check [sms-pc-port](https://github.com/chasem-dev/sms-pc-port) and sms-english
for new findings at most once per phase. Add a finding only through the rules
above, and update the review's revision line when you do.

## Track 2: a decompilation-based Apple port

This plan does not move SunPad to the decompilation. Revisit that only when all
of these are true: the GMSE01 decompilation is close to fully source-linked; a
base-relative pointer layout runs on arm64 without low-memory mappings; a Metal
GX backend exists; and the licensing of any reused port code is clear. That
would be a new multi-month project with its own plan.

## Not in this plan

- Copying sms-pc-port code or patches.
- A PowerPC JIT or runtime code generation on iOS.
- Fast-math, removed exception checks or blessed SMC hashes.
- Splitting CPU and video threads (rejected after a confirmed FIFO
  desynchronization).
- Changing the 30 FPS default or the game-data boundary.
