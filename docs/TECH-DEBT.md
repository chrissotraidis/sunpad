# Performance and stability technical debt

- **Assessment date:** 2026-08-12
- **Evidence updated through:** 2026-09-03 (Preview 8 Issue #12 Noki Bay log)
- **SunPad source assessed:** `54a5f78965b9075bb25427492a266eaad756f64c`
- **Scope:** GMSE01 USA revision 0, Apple ARM64, original 30 FPS and the
  default-off experimental 60 FPS mode
- **Assessment type:** source review, generated-module inspection, retained
  physical-iPad telemetry and CPU-report analysis; no new gameplay run

This is the canonical starting point for future SunPad performance and 60 FPS
work. It records diagnosis and acceptance criteria only. It does not make the
experimental mode supported and does not authorize removing correctness guards,
enabling a PowerPC JIT, or weakening the project's game-data boundaries.

The companion [Apple-platform performance research](APPLE-PERFORMANCE-RESEARCH.md)
turns the iPhone/iPad findings into an offline-first measurement and experiment
plan. It does not authorize another device install or a release.

The [improvement plan](IMPROVEMENT-PLAN.md) (October 2026) orders the next work
into nine passes with scope, effort and device gates. It draws on the
[sms-pc-port research review](SMS-PC-PORT-REVIEW.md). The queue below remains
the record of evidence and acceptance rules that the plan builds on.

## Executive verdict

SunPad has two related but distinct problems:

1. **General performance has limited CPU headroom.** The strongest retained
   sample is dominated by the generated `gGMSE01_recomp.dylib`, not by Metal.
   The module is native ARM64, but it is a large, strict-semantics translation
   of PowerPC code with substantial dispatch, memory-access, and paired-single
   helper work. iOS also uses an interpreter for code outside verified AOT
   coverage and a portable vertex loader because runtime code generation is not
   permitted.
2. **Experimental 60 FPS is not only a throughput problem.** It uses Dolphin's
   live Gecko handler to modify a game designed around an approximately 30 Hz
   update target. The patch creates two AOT hash mismatches, sends two complete
   16 KiB game-code chunks to the PowerPC interpreter, and runs the Gecko guest
   handler outside the module's AOT range. More importantly, the sustained iPad
   pass still delivered near-60 rendered FPS and near-real-time emulation speed,
   yet hands-on play was judged unusable. The exact gameplay symptom was not
   captured. Therefore interpreter overhead is confirmed debt, but it is **not
   proven to be the sole cause** of the failed 60 FPS experience.

The current evidence does not support “Metal is too slow” as the general root
cause. Metal/EFB synchronization can still cause scene-specific hitches and
must be measured rather than dismissed.

## Evidence and confidence

### Confirmed

- Seven retained physical-iPad `cpu_resource` reports recorded 58%-99% average
  CPU. They are energy/performance warnings; each says `Action taken: none`.
- One symbolizable report sampled 33 stacks. Twenty-seven entered the generated
  module through `chassis_dispatch`; observed module frames included large
  translated chunks and paired-single helpers such as `ppc_ps_add_op`,
  `ppc_ps_madd_op`, `ppc_psq_store`, and `psq_store_value`. This is direct
  evidence that generated game-code execution can dominate host CPU time.
- The locally generated C module contains 221 translation units, about 226 MB
  of generated C, and compiles to an approximately 81 MB ARM64 dylib. Static
  inspection counted about 965,000 guest-address `case` labels, 178,000 calls
  to `ppc_*` helpers, and 4,000 paired-single helper calls. These are code-shape
  indicators, not dynamic percentages.
- The device module is already a Release build with ThinLTO. Generated chunks
  receive strict floating-point flags and effective `-O2`; this is not an
  accidental Debug/unoptimized build.
- On iOS, unverified/uncovered game code uses `Interpreter::SingleStepInner()`;
  no fallback PowerPC JIT is created. Dolphin's runtime ARM64 vertex-loader
  generator is also replaced with `VertexLoaderType::Software`.
- Dolphin's FPS metric counts host-presented frames. Its speed metric compares
  elapsed emulated core ticks with wall-clock time. Neither proves that
  Sunshine's animation, dialogue, physics, cutscenes, audio, or input timing is
  correct under a game patch.
- The long physical-iPad telemetry capture included 95 experimental samples:
  59.67 average FPS, 1.0004 average speed ratio, nominal thermal state, and one
  recovered 42.1 FPS / 0.897-speed sample. The corresponding original-mode
  samples averaged 29.95 FPS and 1.0017 speed ratio.
- The 60 FPS Gecko code changes instructions inside chunks
  `[0x80005600,0x80009600)` and `[0x802F9600,0x802FD600)`. StaticRecomp correctly
  rejects both whole chunks after their hashes differ and interprets them until
  invalidation. Disabling this check or accepting the original generated code
  against modified guest bytes would execute the wrong instructions.
- While Gecko codes are enabled, Dolphin invokes its guest code handler from
  the VI-timed `PatchEngine` pass. Its entry point is outside GMSE01's AOT
  module range, so SunPad executes that handler through the interpreter too.
- The existing DolRecomp LLVM backend is not an iOS optimization switch. The
  pinned implementation explicitly accepts only x86-64 Linux and Windows
  production targets. An August 13 disposable probe generalized its target
  setup, passed all 19 backend tests, emitted the real GMSE01 DOL as 221 ARM64
  iOS objects, and linked the normal module ABI. The unoptimized result had
  about 1.70 GB of executable text, so the proven target/link path is not a
  viable full module. Hot-region LLVM plus compact C cold code is now the
  relevant design, subject to a tested cross-backend budget/dispatch ABI.
- Upstream Dolphin documents known Sunshine 60 FPS Gecko-code defects,
  including music problems and falling-star artifacts, and requires 60 Hz mode
  to avoid cutscene stutter. Those upstream limitations do not identify the
  exact SunPad hands-on failure, but they show that rendered cadence alone is
  an insufficient support gate.

### Strong inference

- **The first general bottleneck to investigate is CPU execution, especially
  the generated module.** Retained stacks and resource reports support this more
  strongly than a universal GPU-bound diagnosis.
- **60 FPS reduces stability margin even when it reaches 60 FPS.** It requests
  roughly twice the game update/render work, adds live Gecko-handler work, and
  introduces interpreter-only regions on a path that already has sustained CPU
  pressure.
- **Paired-single and translated memory helpers are likely optimization targets.**
  They appear in sampled hot stacks and occur throughout the generated module.
  A time profile must rank specific helpers and guest PCs before implementation.
- **The portable vertex loader is a plausible secondary CPU cost.** Source
  inspection proves it is selected; current evidence does not quantify its
  share.
- **Some short hitches may be CPU/GPU synchronization rather than shader fill.**
  Dolphin's EFB copy and Metal staging paths contain explicit pipeline flushes
  and `waitUntilCompleted` points. The existing telemetry has no counter or
  duration for those waits.

### Unresolved

- Why the hands-on 60 FPS session was unusable. The test record did not classify
  animation, physics, dialogue, cutscene, audio, input, save, or camera defects.
  sms-pc-port needed 35 game-side timing fixes beyond reporting the higher rate
  (wipes, gates, timers, flocks, sway, rides, bosses, ripples, particles and
  sound). The six-line Gecko code cannot make those fixes, so objects running
  at the wrong rate are a likely cause. This is an inference until a run
  classifies the failures.
- Which optimizations can safely recover the reproduced original-30-FPS
  iPhone 14 deficit. August 13 captures at native 1x reproduced both
  nominal-thermal 25.7-27.1 FPS / 0.872-0.910 speed and serious-thermal
  23.0-25.9 FPS / 0.785-0.875 speed. The CPU-GPU thread repeatedly reached
  99.8-99.9%, while lighter intervals recovered in the same process. A
  weighted 30-second CPU profile attributed 17.8% of sampled CPU cycles to
  the guest scheduler wait loop at `80348814`. The existing cycle-aware idle
  seam reduced that loop to 1.7% in a confirmation profile. A DOL-only native
  resolver bypass then removed about 5% of measured address-resolution cost.
  A seven-minute serious-thermal run held approximately real-time speed, but
  a later run still fell to 22.2-23.8 FPS / 0.759-0.773 speed when the game
  thread reached 99.8%, then recovered. The module already uses ThinLTO and
  strict `-O2`, so no missing release flag explains the remaining single-core
  ceiling. Paired-single and quantized-memory helpers, MMU writes, generated
  functions, vertex loading, and dispatch remain the recurring costs.
- Dynamic native-versus-interpreter proportions in representative scenes. The
  counters currently appear only at graceful shutdown, which mobile tests do
  not reliably capture.
- CPU time split among generated game code, interpreter fallback, vertex
  conversion, DSP/audio, graphics submission, and synchronization waits.
- Whether higher render scales materially worsen each reported slowdown. The
  iPhone 14 reproduction proves that native 1x does not eliminate the issue,
  but a matched per-scene scale matrix is still needed.
- Issue #12 remains open on the iPhone 15 Pro. A September 1 Preview 6 report
  (`SP-133DE3C9`) confirms that the one-time migration disabled the old 90%
  experiment and selected original 30 FPS, Original 4:3, and 1x at nominal
  thermals. Five of six ten-second snapshots reported 29.9-30.0 FPS at
  0.998-1.012 speed; one approximately one-second performance window fell to
  20.4 FPS / 0.969 speed and recovered by the next snapshot. The reporter
  described the build as significantly more stable, but the runtime covered
  only about 80 seconds and supplied no scene, frequency, or screenshot. This
  is improved short-run evidence, not a resolved long-session result or a
  subsystem attribution.
- The September 3 Preview 8 report (`SP-83B955CD`) isolates one regression in
  the aspect-ratio workaround. Its process selected 16:9 before returning to
  Original 4:3, then logged the `0x8019D600`–`0x801A1600` chunk as modified six
  times. Dolphin's one-shot `UnsetPatch` does not restore guest memory, so the
  `0x8019F83C` heatwave entry stayed patched and the full 16 KiB chunk remained
  interpreter-only. The run later spent several minutes around 22–28 FPS at
  1× / Original 4:3 in Noki Bay with the combined CPU-GPU thread saturated and
  Serious thermals, then recovered without another settings change. Preview 10
  restores the DOL-verified `0x7C0802A6` instruction and re-invalidates the
  chunk. This removes the confirmed fallback leak; it does not yet prove that
  every Noki Bay slowdown or thermal ceiling is resolved.

## Important non-solutions

- Do not make the FPS label the acceptance result. Report FPS, VPS, speed ratio,
  frame-time distribution, and gameplay correctness separately.
- Do not remove the SMC hash guard or mark modified chunks verified without
  generating native code that matches the modified guest instructions.
- Do not enable Dolphin's PowerPC JIT on iOS. It conflicts with platform policy
  and SunPad's documented execution contract.
- Do not describe the LLVM backend as available for iOS until ARM64 Mach-O
  generation, ABI, signing, module loading, and lockstep behavior are proven.
- Do not lower internal resolution and call the CPU problem fixed. Resolution
  A/B tests are diagnostic; the result may differ between gameplay, map
  transition, water/heat-haze, and dialogue scenes.
- Do not loosen strict floating-point behavior or enable broad fast-math without
  differential correctness evidence. Sunshine uses floating-point and
  paired-single math for gameplay as well as rendering.
- Do not treat reduced fallback/dispatch counters as correctness evidence. An
  August 13 cache-control fast path held full speed but visibly corrupted game
  behavior and froze during screenshot handling; it was rejected and rolled
  back to the original module and cache semantics.
- Do not replace iOS hybrid ubershaders with synchronous specialized-shader
  compilation as a blanket workaround for an initially incorrect shadow. An
  August 13 physical-iPhone A/B made the shadow correct immediately but caused
  black-screen and severe 1-8 FPS compilation stalls as new shaders arrived.
  It was rejected and the asynchronous hybrid mode restored. Investigate Metal
  ubershader equivalence or targeted pipeline warmup instead of blocking play.
- Do not tune the audio queue first for a general frame slowdown. Audio can
  reveal lost real-time speed, but the known guest-timebase producer bug is
  already fixed and buffering changes can hide rather than remove CPU stalls.
- Do not treat removal of the iOS `Failed to allocate memory space: 0x3`
  startup message as a performance fix. StaticRecomp's empty block cache never
  stores JIT blocks; disabling its unused 64 GiB entry-point-map reservation
  removes misleading diagnostic noise without changing game execution.

## Work queue

### P0: make save writes atomic

Dolphin's GCI folder rewrites each save in place with a truncating open, and
its loader skips any GCI whose size does not match its header. A termination
during a write can therefore hide a save from the game. Write through a
temporary file and rename, keep one last-good backup, and repair or restore
short files on load. See [pass 1](IMPROVEMENT-PLAN.md#pass-1-save-durability).

### P0: make the next reproduction decisive

No performance implementation should begin until one build exposes the
following bounded diagnostics at runtime and in the shareable log:

1. FPS, VPS, speed ratio, average/p95/p99 host frame time, and longest frame.
2. Delta native dispatches, interpreter steps, hook fallbacks, native
   exceptions, failed SMC chunk count, and the currently interpreted PC/chunk
   histogram.
3. CPU/GPU synchronization count and accumulated wait time, including Metal
   staging waits and EFB-copy-triggered flushes.
4. Vertex count/batches and time spent in portable vertex loading.
5. Audio callback cadence, queue depth, underrun/prebuffer events, and dynamic
   resampling correction.
6. Process thermal state, Low Power Mode, memory footprint, and application CPU
   time. OS-wide percentage alone is not an adequate subsystem profile.

The overlay should show at least FPS, VPS, and speed percentage. Logging remains
once every ten seconds, with a small retained worst-frame summary, so diagnostics
do not become the bottleneck.

Acceptance:

- counters can be read without stopping the game;
- logging remains bounded and contains no personal/container paths;
- enabling diagnostics causes no material frame-rate or audio regression; and
- a graceful shutdown summary agrees with the accumulated live deltas.

### P0: establish a repeatable scene matrix

Capture the same route on the same device and build:

| Scenario | Modes | Purpose |
|---|---|---|
| Title/attract | 30 and 60 FPS, 1x and 2x | Low-interaction baseline |
| Delfino Plaza traversal | 30 and 60 FPS, 1x and 2x | Representative game/geometry load |
| Dialogue/cutscene | 30 and 60 FPS | Identify simulation or presentation-time defects |
| Map open/close transition | 30 and 60 FPS, 1x and 2x | Stress known EFB/backend synchronization behavior |
| Water/FLUDD/heat haze | 30 and 60 FPS, 1x and 2x | Stress effects, EFB copies, and vertex work |
| Save, reload, background/resume | both modes | Stability and persistence boundary |

Record screen video or timestamps alongside the log. A run passes only when
telemetry and hands-on observation agree. Repeat after 15 and 30 minutes to
separate scene cost from thermal or accumulating-state behavior.

### P1: replace live Gecko execution for any serious 60 FPS prototype

The next 60 FPS architecture should produce native code that matches the
modified game behavior. It must not simply bless changed hashes.

Preferred investigation:

1. Decode all six lines of the bundled GMSE01 Gecko code: three direct writes,
   the C2 injection header, and its two payload lines including branch/return
   behavior.
2. Build a separate, explicitly identified 60 FPS module variant in which the
   changed instructions or equivalent game-specific replacements are compiled
   ahead of time and included in module hash metadata.
3. Ensure the guest RAM bytes, native implementation, and SMC hashes describe
   the same program before first dispatch. SunPad currently boots the disc
   image, so generating a patched module alone is insufficient.
4. Disable the generic Gecko handler in that variant. Confirm zero unexpected
   SMC failures and near-zero interpreter work in the affected regions.
5. Retain original 30 FPS as the supported default and keep the experiment
   restart-required. Never reuse a 60 FPS module with an unpatched 30 FPS guest.

Smaller SMC chunks around the two modified addresses may be useful as a
measurement experiment because they would reduce the amount demoted. They do
not remove the interpreted Gecko handler, do not prove correct gameplay, and
are not the preferred shipping design.

Acceptance before calling the prototype technically improved:

- the exact patch transformation is reproducible from reviewed source;
- module identity prevents 30/60 guest-module mismatch;
- no generic Gecko handler executes during play;
- no expected patch address causes SMC demotion;
- native/interpreter counters improve in matched scenes; and
- lockstep or equivalent differential tests cover each changed instruction and
  replacement boundary.

### P1: profile and optimize the AOT module

1. Produce a symbol-rich Release device module and an address-to-guest-PC map.
2. Capture Instruments Time Profiler data for the scene matrix. Rank generated
   chunks, dispatcher cost, paired-single helpers, memory helpers, host calls,
   and interpreter PCs by inclusive CPU time.
3. Benchmark `RECOMPCORE_MODULE_OPT_LEVEL=2` against level 3. The present build
   already has ThinLTO and effective `-O2`; the test is an evidence-gathering
   change, not a presumed fix.
4. Optimize only proven hot helpers/blocks while preserving strict PowerPC
   floating-point behavior. Use desktop lockstep and device scene parity before
   accepting changes.
5. Prototype ARM64/iOS LLVM only for measured hot regions. Basic target and
   module-link feasibility is proven offline, but the full unoptimized module
   is unusably large and LLVM's cross-chunk budget ABI is not directly
   compatible with C chunks. Keep nearer C-backend wins independent.

Acceptance:

- matched-scene CPU time or p95 frame time improves materially;
- native results remain lockstep-correct for the affected blocks;
- audio, saves, physics, and long-session stability do not regress; and
- module size, link time, and cold-start effects are reported with speed gains.

### P1: quantify the portable vertex-loader cost

Add timing/counters around vertex-loader selection and execution. Compare
identical 1x and 2x runs, because vertex conversion is CPU work while raster/EFB
cost scales more strongly with resolution.

If it is material, investigate an ahead-of-time set of non-writable executable
ARM64 vertex-loader specializations or a faster portable path. Any solution must
avoid runtime executable-memory generation on iOS and retain Dolphin vertex
semantics.

### P2: isolate renderer and EFB synchronization stalls

Instrument Metal command-buffer completion, staging-texture waits, EFB copy
flushes, present lateness, and drawable acquisition. Start with map transitions,
heat haze, water, and graffiti rather than changing global hacks.

Acceptance requires a trace showing which wait dominates a hitch and a focused
change that improves that trace without breaking EFB-dependent effects.

### P2: close thermal and long-session stability gaps

Run 30-minute scene-matched sessions on the physical iPad and supported iPhones.
Correlate speed loss with thermal-state transitions and application CPU time.
Preserve saves/settings through install, run, background/resume, and readback.

The first CPU/video-split Build B showed why this gate cannot be replaced by a
short FPS pass. It initially ran at essentially real-time speed at nominal
thermals, then an attached 20.74-second profile captured the reported slowdown
with Serious thermal state, approximately 93% CPU-thread utilization, and 36%
Video-thread utilization. Explicit `userInitiated` QoS kept 97.6% of CPU-thread
samples on performance cores, so the experiment improved immediate scheduling
headroom but did not solve sustained work or power. Compare time-to-Serious as
well as frame/speed distributions before accepting any split-thread mode.

Subsequent confirmed gameplay rejects the split-thread route outright for
Sunshine: Dolphin logged a FIFO Unknown Opcode caused by CPU/GPU desynchrony,
after which Video-thread work collapsed even though displayed FPS/speed stayed
plausible. A 90% emulated-clock, single-thread, `userInitiated` variant avoided
that failure in two later confirmed-gameplay traces at Serious thermal state.
Its combined CPU-GPU thread measured 77.1% and later 58.8%, versus 92.6% in the
degraded QoS-only capture. Keep this underclock route experimental until
hands-on timing/audio/physics and route coverage pass; never infer correctness
from the FPS counter after a FIFO error.

The historical nominal-thermal 60 FPS pass means thermal throttling is not the
general explanation for that run. It remains plausible for phone reports after
several minutes and must be demonstrated per device.

## 60 FPS support gate

Do not change the public support status until all of the following pass on a
physical device:

- no live Gecko interpreter path and no expected SMC-demoted chunks;
- stable FPS, VPS, speed, and frame-time distribution in the scene matrix;
- correct movement, physics, animation, dialogue, camera, cutscenes, audio, and
  controller polling;
- save creation, reload, restart, and return to original 30 FPS without data or
  preference loss;
- background/resume and at least one 30-minute sustained session; and
- a recorded hands-on verdict with exact failures, not only telemetry.

Until then, **60 FPS Patch (Unstable, Restart Required)** remains default-off,
warned, and excluded from support claims.

## Source pointers

- `apple/ios/SunPadGameViewController.mm`: current FPS/speed/thermal sampling.
- `apple/ios/SunPadCoreHost.mm`: Metal, module, render-scale, and 60 FPS setup.
- `scripts/prepare-game.sh`: production portable-C module generation.
- `scripts/ios-build-core-device.sh`: iPhoneOS module cross-build.
- Maintained ModernGekko fork (formerly
  `patches/ModernGekko/0001-sunpad-apple-runtime.patch`): 60 FPS activation,
  software vertex-loader selection, warning/error forwarding, and bounded
  frame/graphics diagnostic snapshots.
- Maintained RecompCore fork (formerly
  `patches/ModernGekko-dolphin/0001-sunpad-ios-runtime.patch`): interpreter-only
  iOS fallback, timebase repair, Metal/iOS, audio changes, and the embedder
  log/Metal command-buffer error hooks. Pins are in
  [DEPENDENCIES](DEPENDENCIES.md#maintained-source-graph).
- `docs/TESTING.md`: retained hardware telemetry and missing hands-on symptom
  classification.
- [Dolphin's Super Mario Sunshine notes](https://wiki.dolphin-emu.org/index.php?title=Super_Mario_Sunshine): upstream game and 60 FPS limitations.
