# Game-Engine Audio Investigation

Last updated: 2026-08-09

## Status

**Root cause found and fixed in the static-recomp CPU core; physical-iPad
re-acceptance pending.** The StaticRecomp core advanced the guest timebase at
1 tick per CPU cycle, while the real Gekko timebase ticks once per 12 CPU
cycles (`SystemTimers::TIMER_RATIO`). Because `SyncIn()` re-seeds the guest
timebase from `GetFakeTimeBase()` at every native-burst boundary, guest
`mftb` ran 12× fast inside a burst and then jumped **backwards** at the next
boundary — a permanently non-monotonic sawtooth clock, with excursions up to
roughly 18k TB ticks (~0.45 ms) per timing slice.

Super Mario Sunshine's JAudio driver is exactly the kind of code this breaks:
`JASystem::TDSPChannel::updateAll()` measures per-subframe `OSGetTick()`
deltas and force-stops active DSP voices (`breakLowerActive(126)`, i.e.
almost every music/voice/effect channel) when the measured ratio drops under
`DSP_LIMIT_RATIO = 1.1`; the SDK AI driver and `__OSInitAudioSystem` also do
tick-delta busy-waits during audio bring-up (doldecomp/sms:
`JASDSPChannel.cpp`, `dolphin/ai/ai.c`, `os/OSAudioSystem.c`).

The fix is included in the complete
[`0001-sunpad-ios-runtime.patch`](../patches/ModernGekko-dolphin/0001-sunpad-ios-runtime.patch)
snapshot:

- advance `ctx->timebase` as `tb_at_SyncIn + charged_cycles / TIMER_RATIO`
  (monotonic within a burst, agrees with `GetFakeTimeBase()` at boundaries),
  in both the burst and host-call paths of `StaticRecompCore::Run()`;
- materialize live `SPR_TL`/`SPR_TU` in `HookSPRRead` (previously returned
  Dolphin's stale cached values);
- add `STATICRECOMP_NO_FALLBACK_JIT=1` so desktop runs can reproduce the iOS
  execution contract (see "Why desktop never showed this" below).

## Verified evidence (2026-08-08, this Mac)

Producer-side captures via Dolphin's `[DSP] DumpAudio` (`dspdump.wav`,
32,028 Hz stereo — the same pre-output tap as the original investigation):

| Run | Core path | Result |
|---|---|---|
| Desktop, fallback JIT enabled (old default) | JitArm64 executed almost everything (682 module dispatches total) | continuous audio — but not a static-recomp test at all |
| Desktop, `STATICRECOMP_NO_FALLBACK_JIT=1`, unfixed | module-dominant (518M dispatches, 53.7B cycles) | continuous audio at RMS level (84.6% loud / 113 s) |
| Desktop, parity mode, **fixed** | module-dominant (643M dispatches) | continuous audio (91.8% loud / 113 s), no regression |
| Desktop, parity mode, unfixed, CPU throttled to ~7% real-time (E-cores) | module-dominant | producer stream still complete in virtual time — slowness alone does not silence the producer |
| **iOS Simulator app, fixed core** (no JIT, full iOS audio stack) | module-dominant | **continuous audio, 92.8% loud over 139 s, boot → title → attract** |

## Why desktop did not show this before the ARM64 handoff repair

The fallback JIT's yield hook (`StaticRecompShouldYieldAt`) was wired only
into the **Jit64 (x86)** dispatcher. On Apple Silicon, JitArm64 did not yield
back to the module, so earlier desktop "static recomp" runs silently executed
almost entirely in Dolphin's JIT — with the JIT's correct timebase. Only iOS
(which builds no JIT) actually ran the module, which is why the symptom looked
iOS-only. `STATICRECOMP_NO_FALLBACK_JIT=1` exposed the honest module plus
interpreter contract on desktop.

This historical gap was repaired on 2026-08-13 by carrying the two-file fix
from ExpansionPak/RecompCore PR #6. JitArm64 now disables fallback block
linking, asks StaticRecomp whether the next address is covered, stores the live
guest PC, and yields back to the AOT module. The no-JIT environment switch
remains available for iOS-parity investigation.

## Reassessment of the 2026-08-06/07 device evidence

The surviving physical-iPad producer dump
(`GMSE01_2026-08-06_20-16-17_dspdump.wav`, captured on the iPad Pro M2 with
the same DumpAudio tap) contains **89 s of continuous game audio** (89.6%
loud), and TESTING.md records the device running at a full 30 FPS. This
contradicts the earlier conclusion that "the emulated JAudio/DSP producer
ceases to advance after its initial buffers": at minimum, music-level output
was present in the raw producer stream on the device.

The three truncated engine-sound comparison WAVs behind that conclusion were
not retained, so they cannot be re-examined. Two readings are consistent with
all surviving evidence:

1. individual lower-priority voices were being force-stopped (~50 ms ≈ 3
   JAudio frames) by the `updateAll` limiter under the sawtooth clock while
   higher-priority music channels survived — per-voice truncation inside an
   RMS-healthy stream; and/or
2. the audible device symptom was dominated by the output/consumer chain
   (the iOS Mixer prebuffer/zero-fill modifications and the
   earlier AudioQueue experiments or the current CoreAudio backend).

Either way the sawtooth clock was a real, load-bearing CPU-contract defect —
the docs' own leading suspect ("the static recompiler's CPU/timing
contract") — and it is now fixed and verified against the full iOS stack in
the Simulator. Note: `DSPThread = True` found in the device config is inert —
DSP HLE ignores the thread flag.

## Acceptance gate (unchanged)

A physical-iPad run with the fixed core must show a continuous pre-output
DSP dump (DumpAudio) **and** audibly complete title music, the "Super Mario
Sunshine!" title call, and untruncated gameplay effects. If audible problems
persist while the dump is clean, the remaining defect is in the iOS
output/consumer chain (Mixer iOS modifications or CoreAudio), not
the emulated producer, and should be debugged there — do not re-tune the
producer.

## Evidence boundary

WAV captures, the retail image, extracted game data, generated modules,
device containers, and device console logs remain local and gitignored. This
repository contains only findings, patches, and source-side integration.
