# SunPad improvement plan

- **Date:** 2026-10-07
- **Status:** planned work; nothing in this document is implemented yet
- **Baseline:** SunPad `c77dd61`, DolRecomp `fa0cf619`, Apple RecompCore lane
  as pinned in [dependencies.lock.json](../config/dependencies.lock.json)
- **Inputs:** [sms-pc-port research review](SMS-PC-PORT-REVIEW.md),
  [Apple performance research](APPLE-PERFORMANCE-RESEARCH.md),
  [performance technical debt](TECH-DEBT.md)

This plan makes SunPad faster on older hardware without changing what it is: the
retail Sunshine program, translated ahead of time, on the Dolphin-derived
runtime. Each pass is small enough to review on its own, has a measurable
acceptance rule, and lands in the fork that owns the code.

## Goals

1. **Never lose a save.** A crash or iOS termination during a save leaves the
   previous save or the new one intact.
2. **Hold original 30 FPS on iPhone 14 class hardware (A15) in the scene
   matrix.** The worst measured iPhone 14 interval ran at 0.759 speed with the
   game thread saturated, so the critical path needs about 24% less work
   (about 32% more throughput). Older chips are measured after that target is
   met; no promise is made for them yet.
3. **Know where every frame goes** on device, by subsystem and by named game
   function, from a repeatable route.
4. **Then add features** that the extra headroom pays for: HD texture packs,
   a real 60 FPS mode for Macs and M-series iPads, and widescreen polish.

## What changes and why it should be faster

Measured CPU shares from retained iPhone profiles
([APPLE-PERFORMANCE-RESEARCH](APPLE-PERFORMANCE-RESEARCH.md#retained-cpu-profiles)).
These captures are not a matched A/B and their shares must not be added up as
one budget.

| Cost | Share in captures | Pass that targets it |
| --- | --- | --- |
| Paired-single, quantized and FP helpers | 9.7-29.3% (27.4% of the CPU thread in one Build B trace) | 4 (exact native math) |
| Dispatch | 4.0-8.2% | 3 (safe direct calls) |
| Address resolution | 1.2-5.3% | 3 (safe direct calls) |
| FP availability guard | 2.5-3.0% | Already inlined in pinned DolRecomp `fa0cf61`; re-measure in pass 2 |
| Quantized load/store (`psq_l`/`psq_st`) | inside the helper row above | 3 (runtime fast path) |
| Software vertex loading | 0.2-7.3% | 5 (specialized loaders) |
| GPU readback waits | not measured; blocked time does not appear in CPU samples | 2 then 6 |
| Generated game functions | 17-63% | 2 names them; 3 and 4 shrink their call overhead |

The August captures predate the pinned DolRecomp. Since then DolRecomp has
gained an inline FP-enabled check, inlinable paired-single call sites, and an
opt-in direct-call path for cross-chunk calls, so some shares above are already
smaller in the current module.

sms-pc-port is fast because game calls are native calls, math is host floating
point, and graphics skip hardware-command emulation. Passes 3 and 4 bring the
first two into SunPad's translated code. Pass 6 removes the GPU waits that
Sunshine's per-frame readbacks cause. Pass 5 is the vertex-loading part of the
third.

Reaching the 24% target in the worst scene is plausible from passes 3 to 6
together. It is not promised: pass 2 re-ranks the work with real numbers before
the larger passes start.

## Ground rules

- **No sms-pc-port code.** It has no license. Use its documented findings and
  re-derive behavior from the CC0 decompilation, Dolphin and SunPad's own
  measurements. Cite the port where a finding came from.
- **Retail behavior is the reference.** Every native replacement and code
  generation change must match the generated original or the interpreter bit
  for bit, including CPU state the caller can observe. No fast-math, no
  removed exception paths, no blessed SMC hashes.
- **Owning forks.** Compiler changes go to DolRecomp, runtime changes to
  RecompCore/ModernGekko, app changes here. Update pins, gitlinks and the lock
  together ([CONTRIBUTING](../CONTRIBUTING.md)).
- **Evidence is separate.** Unit tests, desktop lockstep, Simulator, device
  telemetry and hands-on play are separate gates. A pass is done only when its
  device gate passes.
- **Original 30 FPS stays the default.** New behavior ships default-off or
  behind a developer launch argument until its gate passes.
- **Protect player data.** Back up and read back saves and settings around every
  device install, as [TESTING](TESTING.md) already requires.

## Passes

| # | Pass | Main change | Where | Effort | Device gate |
| --- | --- | --- | --- | --- | --- |
| 1 | Save durability | Atomic GCI writes, last-good backup, short-file repair | RecompCore | 3-5 days | Kill-during-save and background tests keep the save |
| 2 | Measurement | Named profiles, frame breakdown, repeatable route | SunPad, RecompCore, scripts | 2-2.5 weeks | Same route gives repeatable numbers on iPhone 14 |
| 3 | Safe direct calls and quantized fast path | Make DolRecomp's existing direct calls respect chunk validation, then enable them; add a `psq` fast path | DolRecomp, RecompCore | 2-3 weeks | Lockstep exact; dispatch share falls; matched route faster |
| 4 | Exact native math | Host versions of hot SDK/MSL routines through the replacement hook | Module replacement source, DolRecomp | 3-4 weeks | Bit-exact differential tests; helper share falls |
| 5 | Specialized vertex loaders | Templated loaders for Sunshine's observed formats | RecompCore | 1.5-2 weeks | Byte-identical to software loader; loader share falls |
| 6 | GPU readback waits | Tile/defer settings, then one-frame-latency answers for Sunshine's peeks and pixel metrics | RecompCore Metal/VideoCommon | 1.5-2 weeks, only if pass 2 shows waits | Goop, sun flare and copies render correctly; wait time falls |
| 7 | HD texture packs | Expose Dolphin custom textures with a Files folder | SunPad, RecompCore | 1-1.5 weeks | Memory and load-stutter limits per device |
| 8 | Real 60 FPS | Native timing replacements in place of the Gecko code | Module replacement source | 4-6 weeks | Scene matrix and hands-on verdict on Mac and M-series iPad |
| 9 | Widescreen polish | HUD and fader fixes for 16:9 | Module replacement source or GMSE01 codes | 1-2 weeks | Reported 16:9 scenes correct |

Effort is focused engineering time for one maintainer working with AI
assistance. It excludes waiting for reporters and assumes device sessions can
be scheduled within the same week.

## Pass 1: save durability

**Problem.** `GCMemcardDirectory::FlushToFile` opens each dirty save with
`"wb"` and writes it in place. If the process dies mid-write, the file is
shorter than its header says. On the next launch the loader skips that file
without a message, so the game sees no save and may offer a new file.
sms-pc-port hit the same failure and fixed it with temp-file writes and
load-time repair.

**Change, in the Apple RecompCore lane:**

1. Write each GCI to `<name>.gci.tmp`, `fsync` it, then `rename` over the
   original. Do the same for the card header file.
2. Before replacing a save, keep the previous good file as `<name>.gci.bak`
   (one generation).
3. On load, if a GCI is the wrong size, or a `.tmp` is newer than its target,
   copy the damaged file aside as `.damaged`, then load the `.bak` if one
   exists. Log it once and show a short in-app notice.
4. Keep the existing lifecycle flush and two-second background grace; add a
   log line when a flush completes so a report can show it.

**Out of scope.** tvOS purgeable storage (already documented), cloud sync and
export UI.

**Verification.** Desktop fault-injection test that stops the writer after
each block and asserts the next load sees the old or new save. Device: make a
save, background and kill during the flush window, relaunch, and compare hashes
with the backed-up copy. Upstream the change to Dolphin if accepted here.

**Effort.** 3-5 days plus one device session.

## Pass 2: measurement

This is the existing P0 in [TECH-DEBT](TECH-DEBT.md#p0-make-the-next-reproduction-decisive),
made concrete with three tools the research review showed are cheap.

**2a. Named profiles (2-3 days).** Add `scripts/fetch-gmse01-symbols.sh`:
download `config/GMSE01/symbols.txt` from sms-english at a pinned commit,
check its SHA-256, check that its `build.sha1` equals the extracted
`main.dol` SHA-1, and convert it to DolRecomp's `address size name` map. Keep
the output under the ignored game workspace. Add `scripts/symbolize-profile.py`
to rename `func_80XXXXXX` frames in exported Instruments call trees. Optionally
pass the map through `moderngekko-port build` to DolRecomp `--map` so the
module exposes `DOLRECOMP_SYMBOL_*` constants for pass 4.

**2b. Frame breakdown (4-5 days).** Accumulate per-frame time for: generated
code, interpreter fallback, vertex loading, EFB copies, EFB peeks, performance
query waits, other Metal waits, shader compilation, present and idle. Show it in
a developer overlay line and the existing ten-second log line. The overlay
layout in sms-pc-port is the model: one line per stage, in milliseconds per
frame. Logging stays bounded.

**2c. Repeatable route (4-5 days).** Two developer-only launch arguments:

- `-sunpadWarp stage,scenario` loads a named area from file select. Implement
  it as a module replacement on the stage-change path, using addresses from the
  symbol map.
- `-sunpadInputScript path` feeds a recorded input script to the existing input
  pipe, keyed to the emulated frame count so replays do not depend on
  wall-clock time.

Define three routes from a copied diagnostic save: Delfino Plaza traversal, Noki
Bay (the reported slowdown), and a water, goop and heat-haze scene.

**Gate.** Five runs of the same route on the iPhone 14 agree within a stated
tolerance, and the breakdown accounts for the frame time.

## Pass 3: safe direct calls and the quantized fast path

**Problem.** By default the C module returns to the RecompCore dispatcher
(the chassis) on every call between chunks. Each round trip scans REL
sections, looks up host-call hooks, runs mod dispatch and flushes the cycle
count. The callee's `blr` then re-enters the caller through a `switch` on the
program counter. Sunshine's C++ makes many such calls.

Pinned DolRecomp `fa0cf61` already contains the fix: a cross-chunk `bl` can
call the target chunk directly, resume inline when the callee returns to the
next instruction, and fall back to the chassis on any other exit, with a call
depth limit of 24. It is off unless `DOLRECOMP_UNSAFE_DIRECT_CALLS=1` is set at
generation, because a direct call skips the chassis check that retires chunks
whose bytes no longer match their hash (Gecko codes, the heat-haze patch).
SunPad does not set it.

Separately, the emitter writes `ppc_psq_load_inline` and `ppc_psq_store_inline`
so a hosting runtime can supply a fast path. In the pinned sources those names
forward to the out-of-line helpers. DolRecomp's history records about 4% from a
real fast path in another title.

**Change.**

1. In RecompCore, export a read-only per-chunk "verified" byte array to the
   module, updated wherever chunk state changes.
2. In DolRecomp, make the direct-call site check that flag and leave through the
   chassis when the target chunk is unverified or failed, so the chassis still
   verifies on first entry and still retires modified chunks.
3. Resolve host-call hook addresses and mod-dispatch targets at module load into
   a bitmap the call site also checks. Replacement targets (pass 4) never take
   the direct path, because the direct call enters the original chunk.
4. Confirm that skipping the per-call cycle flush leaves scheduled events
   (interrupts, timers, audio DMA) on time, using the existing lockstep
   harness. If it does not, flush at the call site.
5. Rename the gate to a safe option, enable it for SunPad's module, and keep an
   off switch for A/B builds.
6. Add a RecompCore fast path for `psq_l`/`psq_st` with an unquantized
   (type 0) GQR and a MEM1 address, falling back to the existing helper for
   every other case.

**Verification.** DolRecomp tests for call, return, budget expiry and
exceptions inside the callee, an invalidated target, a hooked target and the
depth limit. Desktop lockstep against the interpreter over the title, plaza and
Noki routes, using DolRecomp's documented A/B protocol (interleaved pairs,
reversed-order block, stated noise floor). Regenerate the GMSE01 module and
update `tests/test-generated-gmse01-audit.sh`. Report module size and link
time.

**Gate.** Lockstep exact; the 60 FPS and widescreen modes still demote exactly
their patched chunks; dispatch share falls in the pass 2 breakdown; matched-route
p95 frame time improves on the iPhone 14.

**Effort.** 2-3 weeks, most of it in tests and lockstep.

## Pass 4: exact native math

**Problem.** Paired-single and FP helper emulation was the largest named cost in
several captures. Much of it sits in a small set of SDK and MSL routines that
the game calls constantly.

**Change.** Use DolRecomp's existing `dolrecomp_dispatch_replacement` hook
with exact addresses from the symbol map. The hook runs when a call reaches the
module through the chassis; pass 3 keeps replacement targets off the direct
path so every call reaches it. Candidates, in the order pass 2 ranks them:

- `PSMTXConcat`, `PSMTXMultVec`, `PSMTXMultVecArray`, `PSMTXMultVecSR`,
  `PSMTXInverse`, `PSMTXCopy`, `PSMTXIdentity` and the other paired-single
  `PSMTX`/`PSVEC` routines the DOL links;
- `J3DPSMtxArrayConcat` and other J3D paired-single routines that rank high;
- MSL `sinf`, `cosf`, `atan2f` and the rest of the list in the review.

Each replacement reads and writes guest memory through the runtime's memory
helpers, computes with Gekko rounding (single rounding for fused operations,
the same `frsqrte`/`fres` estimate helpers the generated code uses, 25-bit
`fmuls` operands), writes the same values the original leaves in observable
registers, and charges the original's cycle count so emulated timing is
unchanged. If FP is disabled or an argument would fault, it calls the original
through `dolrecomp_call_original`. The sms-pc-port notes are a checklist of
these rules; the code is written from the DOL's instructions and the CC0
decompilation.

**Verification.** A desktop differential harness runs each replacement and the
generated original on at least one million random inputs, plus NaN, infinity,
denormal and aliasing cases, and compares memory and CPU state bit for bit.
This mirrors the port's `qemu-ppc` checks, with SunPad's lockstep-tested
generated code as the reference. Then route lockstep and device gate.

**Gate.** Bit-exact harness; helper share falls; no visual or physics change in
the routes.

**Effort.** About a week for the harness and first routine, then half a day to a
day per routine; 3-4 weeks for 15-25 routines.

## Pass 5: specialized vertex loaders

**Problem.** iOS cannot use Dolphin's runtime-generated ARM64 vertex loader, so
it uses the generic software loader, measured at up to 7.3% in one degraded
scene. sms-pc-port's per-VAT readers more than halved its own vertex-loading
time without generating code at run time.

**Change.** Record the vertex formats Sunshine uses on the pass 2 routes.
Generate C++ template specializations for them at build time, select them by
vertex-loader UID, and fall back to the software loader for anything else.

**Verification.** Byte-compare each specialization with the software loader
using Dolphin's vertex-loader test pattern; route lockstep.

**Gate.** Identical output; loader share falls on device.

**Effort.** 1.5-2 weeks.

## Pass 6: GPU readback waits

**Problem.** Dolphin's `GMS.ini` enables EFB peeks, EFB copies to RAM and
performance queries for Sunshine. Each frame the game peeks 17 depths for the
sun flare and one colour for Mario's occlusion, reads goop pixel metrics, and
writes EFB copies back. In the Metal backend, performance-query reads and EFB
peeks that miss the tile cache block the single CPU-GPU thread until the GPU
finishes; EFB copies block when a deferred copy is needed early.

**Change, only if pass 2 shows material wait time:**

1. Measure the existing Dolphin options: `EFBAccessTileSize` (including whole-EFB
   readback), `EFBAccessDeferInvalidation` and `DeferEFBCopies`.
2. If waits remain, add a GMSE01-scoped mode in RecompCore that answers
   peek groups and pixel-metric reads from the previous frame's asynchronous
   readback and reads synchronously only the first time a group appears. This
   is the design sms-pc-port documents, re-implemented for Dolphin's
   `FramebufferManager` and Metal `PerfQuery`.

**Verification.** Screenshots and the frame-hash route for the sun flare
(looking at and away from the sun), goop cleaning progress counters, and
EFB-copy effects. Compare cleaning progress numbers with the synchronous mode.

**Gate.** Identical game-visible results on the routes; wait time falls.

**Effort.** 2 days for the settings A/B; 1-1.5 weeks more for the deferred mode.

## Pass 7: HD texture packs

**Change.** Expose Dolphin's existing custom-texture loading as a setting with a
Files-visible `Textures/GMS` folder that accepts Dolphin-format packs. Size
guidance: the 1080p variant of the community UHD pack (about 156 MB) is the
size class to test on iPhone and iPad; the full UHD pack (986 MB download) is
Mac-only until measured. Keep prefetch off on iOS, log memory use, and turn
packs off automatically after a memory warning.

**Verification.** Memory footprint and load stutter on the iPhone 14, iPad and
Mac routes. Confirm that a texture miss falls back to the original texture.

**Effort.** 1-1.5 weeks. The pack is user-supplied; SunPad does not bundle or
download it.

## Pass 8: real 60 FPS

**Problem.** The current 60 FPS Patch is a live Gecko code. It demotes two code
chunks to the interpreter and was judged unusable in hands-on play. The
port's patch list shows that a correct 60 FPS needs dozens of game-side timing
fixes, which a short Gecko code does not make.

**Change.** Build a 60 FPS mode from native replacements (pass 4
infrastructure): report the active rate from `SMSGetVSyncTimesPerSec`, keep
movement on its 120 Hz ticks, and fix each frame-counting object. Re-derive
every fix from the CC0 decompilation, using the port's list only to find
candidates. Disable the Gecko code in this mode so no chunk is demoted. Target
Macs and M-series iPads first because the mode doubles render and update work.

**Gate.** The existing [60 FPS support gate](TECH-DEBT.md#60-fps-support-gate),
including a written hands-on verdict.

**Effort.** 4-6 weeks after passes 3 and 4.

## Pass 9: widescreen polish

Use the port's documented checklist (camera aspect, full-width fader, HUD panes
kept 4:3 or anchored to edges) to fix SunPad's remaining 16:9 defects. 1-2
weeks, after pass 8.

## Schedule

| Phase | Weeks | Work | Output |
| --- | --- | --- | --- |
| 1 | 1-3 | Pass 1, pass 2 | Saves cannot be cut short; named, repeatable device numbers |
| 2 | 4-10 | Pass 3, pass 4; pass 6 in parallel if waits are material | Faster module and runtime behind developer flags |
| 3 | 11-13 | Pass 5, full scene matrix on iPhone 14, iPhone 15 Pro and iPad | Candidate preview with speed and correctness evidence |
| 4 | 14-22 | Passes 7, 8, 9 | Optional features on hardware with headroom |

The speed work (phases 1-3) is about three months. The full plan is about five.
Each phase ends with a merged, pinned and documented state, so work can stop
cleanly after any phase.

## Success criteria for the speed work

- The pass 2 routes hold 0.98 speed or better at native 1x and original 30 FPS
  on the iPhone 14 for 15 minutes, including after the device reaches Serious
  thermal state.
- No lockstep differences, no new SMC demotions, and no visual, audio, physics,
  input, save or lifecycle regressions in the scene matrix.
- Module size and cold-start time are reported with the speed results.

## Track 2: a decompilation-based Apple port

This plan does not move SunPad to the decompilation. Revisit that only when all
of these are true: the GMSE01 decompilation is close to fully source-linked; a
base-relative pointer layout runs on arm64 without low-memory mappings; a Metal
GX backend exists; and the licensing of any reused port code is clear. That
would be a new multi-month project with its own acceptance plan, not a SunPad
pass.

## Not in this plan

- Copying sms-pc-port code or patches.
- A PowerPC JIT or runtime code generation on iOS.
- Fast-math, removed exception checks or blessed SMC hashes.
- Splitting CPU and video threads (rejected after a confirmed FIFO
  desynchronization).
- Changing the 30 FPS default or the game-data boundary.
