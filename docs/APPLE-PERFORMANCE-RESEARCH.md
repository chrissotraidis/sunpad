# Apple-platform performance research

- **Working date:** 2026-08-13
- **Targets:** iPhone and iPad, original 30 FPS mode, native 1x first
- **Status:** investigation record; not a release claim or a shipping change
- **Device rule:** do not install another experimental build until the capture
  described below is ready to answer a specific question

This document turns the August 2026 slowdown investigation into a repeatable
plan. It supplements [TECH-DEBT.md](TECH-DEBT.md), which contains the broader
performance history and the separate experimental-60-FPS analysis.

## October 2026 update

The [improvement plan](IMPROVEMENT-PLAN.md) supersedes the queue at the end of
this document as the order of work. It keeps this document's evidence rules
and adds four findings:

- **Exact symbols exist.** The CC0 sms-english GMSE01 symbol map matches
  SunPad's `main.dol` by SHA-1 and gives 38,343 addresses and sizes. That
  resolves the "exact GMSE01 symbol/function bounds" requirement for rank 6
  and lets profiles name generated functions.
- **The pinned DolRecomp has moved on.** `fa0cf61` already inlines the
  FP-enabled check that rank 1 proposed. It also emits inlinable paired-single
  call sites, which SunPad's runtime does not yet back with a fast path, and
  an opt-in direct cross-chunk call path that is off because it bypasses chunk
  validation. The August profiles predate these changes.
- **Sunshine reads the GPU back every frame.** Its sun-flare depth peeks,
  occlusion colour peek, goop pixel metrics and EFB copies to RAM each block
  the single CPU-GPU thread in Dolphin's Metal backend. CPU samples do not show
  that blocked time.
- **Save writes are not atomic.** See the plan's pass 1.

The [sms-pc-port review](SMS-PC-PORT-REVIEW.md) records where each finding
came from.

## Current conclusion

The evidence does not identify one universal throttling bug, and it does not
show that an iPhone simply lacks enough GPU power for Sunshine. It shows a
native ARM64 AOT game module repeatedly reaching a single host-thread ceiling.
Several costs can consume the remaining frame budget, and their proportions
change by scene:

1. translated game code and exact PowerPC paired-single/quantized-memory math;
2. dispatch, address translation, and interpreter fallback;
3. Dolphin's portable software vertex loader, required because the normal
   ARM64 loader generates executable code at runtime;
4. Metal pipeline specialization and CPU/GPU synchronization;
5. audio work and recovery when emulation falls behind; and
6. thermal state, thread scheduling, and the instruction-cache cost of a very
   large generated module.

Two narrow CPU changes recovered substantial headroom in some intervals: a
cycle-aware guest idle hint and a DOL-only native-address resolver bypass. A
later interval still dropped to roughly 22-24 FPS and 0.76 speed while the
CPU-GPU thread approached 100%, then recovered in the same process. Those
changes are useful but do not constitute a general fix.

At the worst reproduced 0.759-speed interval, reaching real time requires
roughly a 24% reduction in critical-path work (equivalently, about 32% more
throughput). No single remaining measured cost is that large in every scene.
The credible solution is therefore a combination: make the hottest generated
CPU regions and portable vertex work cheaper, and prevent shader compilation
from competing at the game thread's scheduling priority. The tested CPU/video
split is not part of that path because it produced a confirmed FIFO
desynchronization. A conservative emulated-CPU underclock remains a
compatibility fallback only if its timing and rendering behavior pass the
scene matrix below.

The released Preview 3 90% underclock candidate subsequently produced one
severe visual-corruption report in the Delfino Plaza E.B.S. scene while 4× EFB
rendering (`2560×2112`) was active. The log stayed on the synchronized CPU-GPU
path and showed plausible FPS/speed at nominal thermals, so this is a
correctness failure that ordinary performance counters do not detect. It does
not yet prove whether the trigger is the 90% guest clock, 4× EFB, or their
interaction.

The next diagnostic iteration keeps the single public experimental toggle and
adds developer-only launch profiles:

- `-sunpadExperimentalPerformanceQoSOnly`: 100% clock plus `userInitiated` QoS;
- `-sunpadExperimentalPerformance95`: 95% clock plus `userInitiated` QoS; and
- `-sunpadExperimentalPerformanceMode`: the current 90% clock plus
  `userInitiated` QoS.

Fresh-launch each profile, plus the stable 100%/inherited baseline, through the
same E.B.S. scene at Original 4:3 and both 1× and 4×. If only 90% fails, advance
95% as the next candidate. If both profiles fail only at 4×, investigate the
EFB/Metal synchronization path. If stable also fails, treat it as a shared
renderer/runtime regression rather than an experimental-clock result. Do not
add these developer profiles to the public menu.

Game Mode is worth declaring and testing, but it is scheduling assistance, not
a replacement for this work. Apple says it reduces background activity and
prioritizes the game. iOS determines activation for an eligible game, and the
user can toggle it. It cannot make generated PowerPC operations cheaper or
remove shader and vertex work. See [Apple's Game Mode guidance](https://support.apple.com/105118) and
[`LSSupportsGameMode`](https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsgamemode).

## What the current evidence proves

### Runtime and build shape

- The game CPU path is ahead-of-time generated ARM64 code, not a PowerPC JIT.
- The portable-C module is already a Release/ThinLTO build with strict
  floating-point behavior and effective `-O2` on its generated chunks.
- The generated C is about 226 MB and the linked module contains about 81 MB of
  executable text. Front-end pressure from code footprint is plausible, but
  it has not been measured with CPU counters.
- Static inspection found approximately 136,850 emitted floating-point
  availability checks, 2,375 paired-single helper calls, and 1,703 quantized
  load/store calls in the generated output.
- The C emitter calls `ppc_fp_available` before every floating-point operation.
  The existing LLVM emitter instead tests the common FP-enabled condition
  inline and calls the helper only on the exceptional path.
- The pinned LLVM object backend still accepts only x86-64 Linux/Windows as
  committed, so it is not a switch SunPad can enable today. A disposable
  offline target-generalization probe nevertheless proved that its design is
  not fundamentally x86-only; see the ARM64 result below.
- The runtime explicitly selects `VertexLoaderType::Software` on iOS. Dolphin's
  ARM64 loader normally creates specialized executable code at runtime, which
  is not an acceptable application strategy on iOS.

### ARM64 LLVM feasibility result

On August 13, a disposable copy of DolRecomp was generalized just far enough to
exercise the installed LLVM AArch64 target and iPhoneOS object format. No repo
or device build was changed. The probe:

- passed all 19 DolRecomp tests, including generated execution, floating-point
  semantics, dispatch, and the LLVM pipeline;
- decoded the real GMSE01 `main.dol` with 898,736 text instructions, of which
  898,660 were recognized and 76 were classified as embedded data;
- emitted all 221 chunks as ARM64 Mach-O objects targeting iOS 16;
- linked those objects through the existing module template into an ARM64 iOS
  dynamic library with the normal StaticRecomp exports and no unexpected
  unresolved runtime ABI symbols.

This proves basic target and link feasibility. It does **not** prove gameplay
correctness or performance. The deliberately unoptimized full module contained
about 1.70 GB of executable text, so it is unusable. A partial optimized run
also indicated that compiling every cold chunk through the LLVM backend may
still produce a very large module. The practical design to investigate is a
hybrid: optimized LLVM objects for measured hot regions and the compact C
backend for the rest.

That hybrid is not yet plug-compatible. LLVM emits internal
`func_<address>_budget` calls across chunk boundaries, while C chunks expose the
one-argument `func_<address>` ABI. The implementation must either side-exit from
an LLVM hot region to C through the existing `ctx->pc` dispatcher, or add tested
budget-aware bridge wrappers. Direct LLVM calls should remain only inside a
closed hot-region cluster. This boundary needs lockstep coverage before any
device test.

### Retained CPU profiles

These captures cover different scenes and moments. They establish ranges and
candidate costs; they are **not** a matched A/B and their percentages must not
be subtracted as if they were one.

| CPU category | Menu slowdown | Later degraded interval | Idle + resolver build |
|---|---:|---:|---:|
| Generated game functions | 17.26% | 43.12% | 30.13% |
| Paired-single / PSQ / FP helpers | 29.30% | 9.69% | 22.43% |
| Guest scheduler idle loop | 23.25% | 0.32% | 1.66% |
| Dispatch | 4.00% | 8.19% | 6.27% |
| MMU / external memory | 8.95% | 2.34% | 6.99% |
| Address resolution | 3.46% | 5.25% | 1.22% |
| Software vertex loading | 0.20% | 7.32% | 0.82% |
| FP availability guard | 3.00% | 2.47% | 2.64% |
| Graphics host work | 0.75% | 2.91% | 2.78% |
| Audio host work | below table threshold | 0.52% | 0.21% |
| Other | 9.71% | 17.87% | 24.86% |

The important result is variability. There is no basis for optimizing only the
top row of one capture and calling the phone problem solved.

### Graphics and shadows

The temporary bad shadow and the frame slowdown are related only in the broad
sense that both involve runtime rendering work. They are not proven to share a
root cause.

Dolphin's hybrid ubershader model uses a general shader immediately while a
specialized shader compiles in the background. This avoids blocking the game,
but an incorrect or incomplete general path can temporarily render an effect
differently. [Dolphin's ubershader explanation](https://dolphin-emu.org/blog/2017/07/30/ubershaders/)
describes the compilation tradeoff.

The physical-device experiment that forced synchronous specialized compilation
made the shadow correct immediately, but produced black screens and severe
1-8 FPS stalls as new pipelines appeared. It was correctly rejected. The
current Metal backend also reports that pipeline-cache data is unsupported and
does not use `MTLBinaryArchive`.

Apple's supported long-term mechanism is to harvest and precompile known Metal
pipelines in a binary archive. That may remove compilation spikes for a finite
Sunshine workload without globally blocking gameplay. It is a focused graphics
project, not a safe one-line toggle. See [creating binary archives from
device-built pipelines](https://developer.apple.com/documentation/metal/creating-binary-archives-from-device-built-pipeline-state-objects)
and [`MTLBinaryArchive`](https://developer.apple.com/documentation/metal/mtlbinaryarchive).

### Scheduling and thermal state

The outer SunPad game thread and Dolphin emulation thread are ordinary
`std::thread` instances with no explicit quality-of-service declaration. The
retained samples mostly ran on performance cores, but one later capture included
about 11% efficiency-core samples. That observation does not prove a QoS bug.
It does make QoS a valid controlled experiment.

Do not use legacy thread priorities or blindly mark sustained emulation as
`userInteractive`. A future A/B should record the effective QoS and compare the
default against an appropriate explicit class, most likely `userInitiated`,
while checking UI responsiveness, power, and temperature.

Serious thermal state can reduce available headroom, but it is not a complete
explanation: slow intervals occurred immediately and later recovered without a
new process. A cold/warm matched comparison is still required. Apple's
[Power Profiler](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler)
can correlate power and thermal behavior with the marked gameplay interval.

### CPU/video threading is a real performance lever

SunPad currently leaves Dolphin's `MAIN_CPU_THREAD` setting unset. Dolphin's
non-Android default is `false`, so the retained `CPU-GPU thread` profiles are
not just a label: translated guest CPU execution and graphics processing share
one saturated host thread. Dolphin describes the alternate mode as "Enable
Dual Core (speedhack)." Enabling it can move video work off the guest CPU's
critical path and use another Apple performance core.

This is higher leverage than another logging-only build, but it is
correctness-sensitive. Sunshine has a documented "Shaky Props" synchronization
issue, and synchronizing the GPU thread can cost performance. A CPU/video split
therefore needs a route covering props, water, shadows, loading, saves,
background/foreground, and screenshots. It is a controlled candidate, not a
default to flip without playing the game.

### Shader work can be scheduled and cached better

The emulation and async shader compiler workers are ordinary `std::thread`
instances with no explicit Apple QoS. A narrow Apple-platform policy can mark
the sustained game and video threads `userInitiated` while keeping shader
workers at a lower appropriate class. This cannot repair a permanent CPU
deficit, but it can stop cold-scene compilation bursts from preempting the
critical game thread. Apple documents `pthread_set_qos_class_self_np` for
assigning pthread QoS and recommends using the minimum appropriate class.

Metal binary archives are the complementary compilation fix. They allow known
pipeline functions to be precompiled and reused instead of rebuilt during
gameplay. They target first-run shadow/pipeline stutters, not the sustained
generated-game-code ceiling.

### Other execution work that can become real fixes

- **C-backend fast paths:** inline the common FP-enabled test, inline the common
  MEM1/MEM2 access path, and specialize only measured paired-single helpers.
  The FP guard alone measured about 2.5-3%; these are additive wins, not a full
  answer individually.
- **AOT vertex loaders:** record Sunshine's finite `VertexLoaderUID` set and
  generate ordinary build-time ARM64 functions. Dolphin already has a tester
  that compares loaders, so generated output can be byte-compared with the
  software loader. The measured ceiling was scene-dependent, up to 7.3%.
- **Narrow host replacements:** DolRecomp already supports dispatching known
  guest functions to reviewed native replacements. After guest-PC sampling and
  exact GMSE01 symbol identification, one or two genuinely hot SDK/game
  functions could be replaced and differential-tested. Replacing guessed
  functions or using another region's symbol addresses would be unsafe.
- **CPU underclock:** Dolphin and DolphiniOS expose a lower emulated PPC clock
  as a no-JIT performance aid. It reduces required guest work, so it may close
  the last gap on older devices, but it can change timing, physics, audio, and
  loading behavior. It belongs behind an explicit compatibility setting after
  route testing, never as a silent default.
- **VBI skip:** this deliberately skips work when behind. It is a last-resort
  degraded mode, not a general fix, because it can alter visible/game timing.

### Existing logs cannot answer enough

The four supplied Preview 1 diagnostic logs predate the current performance
sampler. They do not contain a subsystem timing breakdown, Game Mode state,
shader compilation durations, audio starvation, guest-PC distribution, or a
replayable scene marker. They can establish environment and configuration, but
they cannot identify the cause of the reported iPhone 15 Pro slowdown.

The current StaticRecomp counters are mainly emitted at graceful shutdown, an
unreliable boundary for a mobile game. The RemoteIO path logs initialization
and an initial callback but not underruns, late callbacks, or mixer depth.
Better logging is therefore a prerequisite, but logging must remain bounded and
must not become another source of stutter.

## Decisive measurement design

The next diagnostic build should expose data at one-second or signposted
intervals and retain only a small worst-interval summary.

### Minimum runtime record

For every interval, record:

- monotonic start/end time and a stable scene/test identifier;
- emulation speed ratio, emulated cadence, presented FPS, and p50/p95/p99 host
  frame time;
- game-thread CPU time and effective QoS;
- thermal state, Low Power Mode, memory footprint, and app lifecycle changes;
- deltas for native dispatches, interpreter steps, native exceptions, failed
  chunks, hook fallbacks, and the top guest PCs;
- software vertex-loader calls, vertices, and elapsed CPU time;
- Metal pipeline requests, cache hits/misses, compile count/duration,
  ubershader fallback count, drawable lateness, and explicit CPU/GPU waits;
- RemoteIO callback lateness, mixer fill level, prebuffer events, and underruns;
  and
- app/runtime/module identity plus render scale, shader mode, dual-core state,
  Game Mode eligibility, and whether shader caches started cold or warm.

The app cannot rely on a public API to report the user's current Game Mode
toggle. The tester must record the state shown in Control Center.

### Instruments capture

Use `OSSignpost` intervals around the exact replay rather than profiling the
entire process and guessing which scene a sample represents. Apple's call-tree
guidance explicitly supports isolating signposted operations and comparing
runs: [Analyzing CPU profiles with call tree views](https://developer.apple.com/documentation/xcode/analyzing-cpu-profiles-with-call-tree-views).

One later hardware session should collect:

1. Time Profiler for inclusive host functions and translated chunks.
2. CPU Counters or Processor Trace for instructions, cycles, IPC, branch
   behavior, and front-end/code-footprint evidence. See [Processor
   Trace](https://developer.apple.com/documentation/xcode/analyzing-cpu-usage-with-processor-trace).
3. Game Performance / Metal capture for pipeline compilation and GPU waits.
4. Power Profiler for thermal and sustained-power correlation.

This is intentionally one coordinated session, not four new installs.

### Repeatable workload

Use a copied diagnostic save and the shortest possible deterministic input
sequence that enters a known Delfino Plaza route. A hidden launch argument or
developer-only test command is sufficient; a new user-facing benchmark system
is not required.

Each run must use:

- the same device, OS, build/module hash, save, route, and duration;
- native 1x first, original 30 FPS, fixed brightness, Low Power Mode off;
- no screen recording and no charging during the measured interval;
- a cold-shader-cache run and a warm-cache run, labeled separately;
- a cold-device run and a sustained warm run, labeled separately; and
- manual confirmation of Game Mode in Control Center.

The iPhone 14 can establish and iterate the harness. The reported problem is
not closed until the same test passes on an iPhone 15 Pro and at least one
supported iPad.

## Ranked implementation and experiment queue

| Rank | Work item | Why it is next | Acceptance / rejection rule |
|---|---|---|---|
| 0 | Offline hybrid ARM64 LLVM ABI prototype and lockstep harness | Full target/link feasibility is proven; hot-only code avoids the full module's size failure | Continue only if C/LLVM boundary tests are exact and optimized hot objects have a plausible size/speed ratio |
| 1 | C-emitter FP and memory common fast paths | Measured additive CPU cost with a small, reviewable semantic surface | Differential instruction tests pass and desktop matched-route time improves; otherwise revert |
| 2 | CPU/video split plus Apple QoS modes | Uses another core and prevents shader-worker contention with the saturated game thread | One diagnostic install; reject on timing, props, shadows, save, lifecycle, audio, or thermal regressions |
| 3 | Hot-region LLVM module | Best chance to materially reduce generated-game and paired-single costs without bloating cold code | Must materially reduce p95 CPU time and retain lockstep/gameplay parity across more than one scene |
| 4 | Ahead-of-time vertex-loader specialization | Software loading reached 7.3% in one degraded scene | Generate only observed finite formats; byte-compare against Dolphin's software loader before device use |
| 5 | Metal pipeline archive or targeted warmup | Addresses cold compilation and temporary shader effects without synchronous stalls | Accept only if cold-cache stalls improve and output matches the specialized path |
| 6 | Exact-symbol native replacement for remaining hot functions | Can remove a large guest function's translation overhead entirely | Require exact GMSE01 symbol/function bounds and differential state tests; no address guessing |
| 7 | Explicit conservative CPU-clock fallback | Provides a way to reach real time if older phones remain below budget | User-visible, restart-required, and rejected if timing, physics, audio, cutscenes, or saves diverge |

## Build A / Build B experimental boundary

Build A remains the published stable SunPad build and uses the existing
single CPU-GPU thread unless a future reviewed release deliberately changes
that default. Build B is the side-by-side `com.sunpad.SunPadPerformanceTest`
application, displayed as **SunPad Experimental**. It exists so performance
work can mature without replacing or destabilizing Build A.

Build B's first restart-selected **Experimental Performance Mode** changes only:

- Dolphin `MAIN_CPU_THREAD` from its stable non-Android default to `true`,
  separating CPU and video work; and
- the host game thread's Apple QoS to `userInitiated`.

It does not change the generated GMSE01 module, shader mode, vertex-loader
selection, Metal backend, audio buffer, render scale, game save, controller
mapping, or touch-control implementation. It is default-off in the shared
runtime configuration and in user preferences. The diagnostic launch argument
`-sunpadExperimentalPerformanceMode` can force it on for a controlled run.

The initial physical-device acceptance rule is deliberately broader than FPS:

1. confirm the log reports experimental mode and the runtime names separate
   `CPU thread` and `Video thread` workers instead of `CPU-GPU thread`;
2. compare the same progressed-save route at native 1x and original 30 FPS;
3. require materially better speed ratio/p95 behavior in the known heavy scene;
4. reject on shaky props, incorrect shadows, water/EFB errors, audio breakup,
   input delay, save/load failure, screenshot freeze, or lifecycle failure; and
5. repeat any apparent win without QuickTime recording before accepting it.

This first Build B does not yet contain the hot-region LLVM backend, C-emitter
fast paths, AOT vertex loaders, or Metal binary archives. Those remain separate
experiments so a failure in CPU/video synchronization is not confused with a
compiler or shader change.

### First Build B device result (2026-08-13)

The signed Release Build B was installed in place over only the existing
side-by-side experimental bundle on the attached iPhone 14. Build A remained
installed and running under `com.sunpad.SunPad`. Build B used the previously
verified known-good module and embedded progressed save; the save hash remained
`e7f31b78b1edb5c38b5e2e9b2f2ccb687b5b96a3ab15158b0220950f9e269cb8`.

The app was launched with `-sunpadExperimentalPerformanceMode`. Console
evidence confirmed:

- experimental performance mode, CPU/video split, and successful
  `userInitiated` QoS assignment (`qosResult=0`);
- original 30 FPS mode at native 1x;
- readable bundled game data, disc image, and signed module;
- runtime creation, RemoteIO initialization/callback, StaticRecomp core start,
  and GMSE01 module load; and
- separate `CPU thread` and `Video thread` samples instead of the previous
  combined `CPU-GPU thread`.

Across ten initial ten-second samples, presented FPS stayed 29.9-30.0 and speed
ratio stayed 0.994-1.009 (mean about 1.005) at nominal thermal state with Low
Power Mode off. Once thread sampling established a baseline, the CPU thread
used about 67-83% and the Video thread about 2%. This is materially different
from the earlier heavy intervals where the combined thread reached 99.8% at
0.759-0.773 speed, but it is not a matched heavy-scene comparison. Hands-on
prop/shadow/water/audio/input/save/lifecycle acceptance and the previously
degraded route remain open.

The same uninterrupted process later changed from subjectively near-perfect
play to obvious slowdown. A 20.74-second Time Profiler capture was attached to
the already-running process, without relaunching the app or changing its
settings. Instruments reported **Serious** thermal state for the complete
21.08-second recorded interval. The CPU thread was running for approximately
93.0% of the interval and the Video thread for 36.2%, compared with the initial
67-83% / approximately 2% observations. This is a real workload and thermal
transition, not merely perceived frame pacing.

Explicit QoS did not fail to place the critical thread: 97.6% of the CPU
thread's running samples were on the two performance cores, with 2.4% on
efficiency cores. The leaf-sample breakdown attributed approximately 63.4% of
CPU-thread samples to generated game functions and 27.4% to PowerPC floating-
point, paired-single, or quantized-memory helpers; 8.9% was outside the module.
This supports the hot-region/compiler work and does not identify the overlay or
UI as the critical-path cause in that interval.

The first Build B result is therefore promising but not shippable. Separating
CPU and video work can recover enough immediate headroom to reach real time,
but it also permits more parallel sustained work and can reach the phone's
thermal envelope. Serious thermal pressure then removes enough headroom for the
slowdown to return. A cold, scene-matched A/B must measure both time-to-Serious
and sustained speed; a short burst result would overstate the benefit.

Later confirmed-gameplay evidence rejected CPU/video splitting for a more
important correctness reason. A 90% emulated-clock variant initially reduced
the CPU workload, but after sustained gameplay Dolphin reported `GFX FIFO:
Unknown Opcode` and explicitly identified CPU/GPU desynchronization caused by
Dual Core. Video-thread utilization then collapsed from roughly 37% to 0.8%
while the FPS and speed counters continued to look healthy. Those counters were
therefore invalid after the desync. Do not ship any Sunshine performance mode
that enables `MAIN_CPU_THREAD`, regardless of its short-term speed.

The final diagnostic variant combined a 90% emulated CPU clock with the stable
single CPU-GPU thread and `userInitiated` QoS. Two traces were started only
after the tester explicitly confirmed that Mario was controllable in gameplay.
Both were captured at **Serious** thermal state. The first 20.68-second trace
measured the combined thread at 77.1%; a later 20.45-second trace measured it at
58.8%. In both, effectively all critical-thread samples remained on performance
cores. No separate Video thread, FIFO Unknown Opcode, or dual-core desync was
observed, and the same PID remained alive between captures.

This proves that the single-core 90% profile creates measurable CPU headroom
and removes the demonstrated dual-core failure mechanism. It does **not** yet
prove a shippable mode: retained FPS/speed telemetry was unavailable from the
post-update console attachment, and the underclock can alter guest timing,
audio, physics, or game logic. The tester's hands-on verdict plus a longer route
covering saves, transitions, water, shadows, props, audio, and lifecycle remain
required before exposing it in the official app.

QuickTime selected the correct iPhone under its **Screen** list but displayed a
stale black capture while the physical phone and device console showed the app
running successfully. The physical display and console are authoritative for
this run. Do not use that QuickTime window as visual evidence until it shows a
current device frame.

### Experiment details

#### C-emitter FP fast path

This is the smallest plausible code-generation optimization. Reproduce the
LLVM backend's existing semantics: check the normal FP-enabled state inline and
call `ppc_fp_available` only when the state requires exception handling. Do not
remove the exception path and do not change floating-point contraction or
rounding flags.

Validation must compare C-emitter and interpreter results across FP-disabled,
FP-enabled, exception, FPSCR, paired-single, NaN, infinity, denormal, and
quantized load/store cases. A 2.5-3% sampled helper cost is an upper bound, not
a promised user-visible gain.

#### Code footprint and PGO

Do not assume `-O3` is faster. The current strict `-O2` module is already large.
If CPU counters show instruction-fetch, branch, or front-end pressure, compare:

- profile-guided function/block ordering from the deterministic route;
- hot/cold splitting and guest-PC-guided chunk layout; and
- `-O2`, size-aware optimization, and the current build on both speed and
  module size.

Profiles must cover more than Delfino Plaza so optimization does not overfit a
single route.

#### AOT vertex loaders

Sunshine uses a finite set of vertex formats during a controlled route. Record
their descriptors, generate normal source/object functions at build time, and
select them without writable executable memory. Dolphin's vertex-loader tester
already provides a useful correctness pattern: compare optimized and software
output byte-for-byte, including cache behavior. Fall back to software for every
unknown format.

#### Metal pipeline work

First identify the pipeline IDs used while the shadow is temporarily wrong and
compare ubershader output with the later specialized output. Then determine
whether the failure is:

- incorrect ubershader equivalence;
- pipeline compilation latency;
- a cache invalidation/key problem; or
- an unrelated texture/EFB synchronization issue.

Only after that should SunPad evaluate Metal binary archives, a finite Sunshine
pipeline warmup set, or a focused upstream Dolphin fix. Global synchronous
shader compilation remains rejected.

## Changes that are not solutions

- Reflashing the same device without a new discriminating measurement.
- Treating Game Mode as a guaranteed turbo switch or controlling it from app
  code.
- Lowering resolution and declaring a CPU-bound scene fixed.
- Removing hash, cache, exception, or floating-point correctness checks.
- Enabling broad fast-math for gameplay code.
- Enabling runtime-generated ARM64 code or a PowerPC JIT on iOS.
- Increasing audio buffering until stutter is less audible.
- Using FPS alone; emulation speed, frame times, audio, and gameplay correctness
  are separate acceptance dimensions.
- Shipping synchronous shader compilation because one shadow initially looks
  better.

## Decision gate for another device build

Do not install a new performance build until all of these are true:

1. The build contains bounded live counters and signposts listed above.
2. A deterministic route and exact capture duration are written down.
3. One diagnostic clone contains the stable baseline plus restart-selected
   CPU/video, QoS, and candidate-module modes. The baseline uses the same
   runtime/module configuration as stable; variants change only their named
   experiment.
4. User game data, save data, settings, and touch controls have a tested
   preservation/read-back procedure.
5. The expected result has a numeric accept/reject rule.
6. The same install can collect baseline and variants by relaunching, without
   another deployment or save migration.

A candidate optimization is not a fix until it passes the route at full
emulation speed, preserves correct shadows/audio/input/saves, survives
background/screenshot recovery, and remains stable during a sustained warm
run. The final matrix must include iPhone and iPad.

## Publication boundary

This file can become the public research record after review. A public version
may include architecture, sanitized aggregate timings, hypotheses, rejected
experiments, acceptance criteria, and upstream links. It must not include:

- disc images, extracted assets, generated game-derived code, or modules;
- saves or application containers;
- signing/provisioning material;
- personal device paths, identifiers, or raw traces containing them; or
- claims that an unvalidated experiment fixes iPhone/iPad performance.

No publication, commit, or push is authorized by creating this working file.

## Immediate next work, still offline

1. Turn the disposable ARM64 proof into a minimal, reviewable DolRecomp target
   change and pin a supported LLVM toolchain version.
2. Define the hybrid hot-region boundary: LLVM-to-LLVM calls may stay direct;
   LLVM-to-C calls side-exit through `ctx->pc`. Add cross-boundary, budget,
   floating-point, memory, and exception tests before compiling Sunshine.
3. Benchmark optimized single hot chunks and clusters against the current C
   objects on desktop. Reject the approach early if object size or route time
   is not credible; do not build another multi-gigabyte full module.
4. Implement and test the narrow C FP/memory fast paths independently so they
   remain useful even if the hybrid backend is rejected.
5. Prepare one diagnostic clone with restart-selected baseline, CPU/video
   split, QoS, and candidate-module modes. Preserve the existing save, game
   path, settings, and touch controls.
6. Use QuickTime to preserve visible/audio symptoms and a "bug now" marker,
   and use a simultaneous signposted Instruments Game Performance trace for
   causality. Because recording can change the audio route and add load, repeat
   the winning quantitative run without recording before accepting it.

This sequence uses the attached iPhone once the candidates exist; it does not
use the phone as a compiler experiment loop.
