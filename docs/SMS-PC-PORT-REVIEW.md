# sms-pc-port research review

- **Date:** 2026-10-07
- **Reviewed:** [chasem-dev/sms-pc-port](https://github.com/chasem-dev/sms-pc-port)
  at `89e9fd01602bfa9735cdb1d5713d39edff91d9e7`, with its decompilation submodule
  pinned at `967436b8c623834d38a57d34923775f45eca8861`
- **Symbol data checked:** [chasem-dev/sms-english](https://github.com/chasem-dev/sms-english)
  `config/GMSE01/symbols.txt` at `d5f4eb3eb54ac49638b5513efb1fc368068805da`
  (SHA-256 `c75a8f35c1d51e7978cc66aeaa86c1d4e2d16c5603576183e0cd49e66a8d98ff`)
- **SunPad baseline:** `c77dd61` on `main`
- **Method:** source and documentation review. The port was not built or run,
  and no SunPad device build was made for this review.

SunPad uses sms-pc-port as a research reference. It is a different kind of
port, so it cannot be merged into SunPad, but its documentation and code
explain several Sunshine behaviors that SunPad pays for today. The
[improvement plan](IMPROVEMENT-PLAN.md) turns those findings into scoped work.

## What sms-pc-port is

sms-pc-port compiles the Super Mario Sunshine decompilation (`sms-english`, a
CC0 GMSE01 fork of [doldecomp/sms](https://github.com/doldecomp/sms)) as ordinary
host C++. It replaces the GameCube SDK with host code: a GX-over-OpenGL 3.3
renderer, a software DSP mixer, disc and memory-card services, SDL input, and
OS/thread emulation. Game data still comes from the user's disc image at run
time.

| | SunPad | sms-pc-port |
| --- | --- | --- |
| Game code | Retail `main.dol` translated ahead of time to ARM64 by DolRecomp | Decompiled source compiled natively |
| Hardware layer | Dolphin-derived runtime (RecompCore) emulating GX, DSP, memory and timing | Host replacements for SDK calls |
| Renderer | Dolphin Metal backend | Own OpenGL 3.3 backend (about 4,700 lines at introduction) |
| Apple targets | iPhone, iPad, Apple silicon Mac, experimental Apple TV | x86_64 macOS only; Apple silicon through Rosetta 2 |
| Game-code fidelity | Retail machine code | 72.94% byte-perfect functions (12,002 of 12,904); 33.18% source-linked objects; 216 port patches |
| Age | Preview series since August 2026 | Repository created 2026-09-24 |
| License | GPL-3.0-or-later | No license file (all rights reserved by default) |

## Why it cannot be dropped into SunPad

1. **Apple ARM64 cannot host its memory model.** The decompiled game stores
   pointers in 4-byte fields, so every game-visible address must stay below
   4 GiB and main memory is mapped at `0x80000000`. Native arm64 macOS and iOS
   reserve the low 4 GiB as `__PAGEZERO`. The project's own `BUILD.md` and
   `CMakeLists.txt` reject native arm64 for this reason. An Apple port would
   need every pointer-in-`u32` site converted to a base-relative offset; the
   project's `PTR32` type is the start of that work, not the end.
2. **OpenGL is not an iOS option.** The renderer targets desktop OpenGL 3.3
   core. iOS would need a new Metal backend.
3. **No license.** Code without a license cannot be copied into a GPL project.
   SunPad may read it, learn from its documented findings, and re-derive
   behavior from the CC0 decompilation, but must not copy its source or patches.
4. **Unmatched game code.** About a quarter of functions are not yet
   byte-matched. Open reports include a Linux crash when collecting a 1-UP in
   Bianco Hills (issue #25) and another crash report (issue #28). SunPad runs
   the retail instructions, so it does not inherit decompilation mistakes.

The speed difference is real but structural. Game calls are native calls, math
is host floating point, and GX calls skip Dolphin's hardware-command emulation.
SunPad can close part of that gap inside its current architecture; the plan
names where.

## Findings that transfer to SunPad

### 1. Exact GMSE01 function boundaries are now available

`sms-english` publishes a CC0 GMSE01 symbol map with 38,343 entries, each with
an address and size. Its required executable hash, `a6782903ef79d4196c8489ecb1b57decb5b3728f`,
matches the SHA-1 of SunPad's extracted `main.dol`, so the map describes the
exact program SunPad recompiles. Examples: `PSMTXConcat` at `0x803499F0`
(`0xCC` bytes), `PSMTXMultVec` at `0x8034A2D0`, `PSVECNormalize` at
`0x8034A5D0`, `sinf` at `0x8033C7E4`, `J3DPSMtxArrayConcat` at
`0x802D3404`.

This removes the blocker recorded for rank 6 of the
[performance research](APPLE-PERFORMANCE-RESEARCH.md#ranked-implementation-and-experiment-queue):
native replacements required "exact GMSE01 symbol/function bounds". It also
lets SunPad name the generated functions that dominate CPU profiles. DolRecomp's
`--map` parser already accepts `address size name` lines, so conversion is a
small script.

### 2. A catalog of the hot math the game calls, with exact semantics

`docs/64-BIT.md` and `platform/mtx` document which matrix and vector routines
the DOL links (24 paired-single `PSMTX`/`PSVEC` routines plus six C routines),
which MSL math functions it calls (`sinf`, `cosf`, `tanf`, `atanf`,
`atan2f`, `acosf`, `expf`, `powf`, `fmodf`, `sqrtf`), and the inlined
`frsqrte` square-root helpers (`JGeometry::TUtil<f32>::sqrt`, `inv_sqrt`,
`MsSqrtf`). It also records the Gekko rounding rules a host must follow:
single rounding for fused multiply-add, the `frsqrte`/`fres` estimates,
25-bit operand rounding in `fmuls`, saturating `fctiwz`, and Gekko NaN
behavior. Each host version was checked bit for bit against the original
objects run under `qemu-ppc` on one million inputs per function, with
documented workarounds for qemu's missing paired-single instructions and
exact estimates.

SunPad's profiles put paired-single, quantized and floating-point helpers at
10-29% of CPU in different captures. Native replacements for the hottest of
these routines are plausible, and the port's verification method is the right
acceptance test.

### 3. Sunshine reads the GPU back every frame

Comments in `platform/gx/src/gx_render.cpp` identify three per-frame
GPU-to-CPU reads:

- the sun's lens-flare test peeks 17 depth values and Mario's occlusion test
  peeks one colour (`GXPeekZ`/`GXPeekARGB`);
- Delfino's pollution counters read pixel metrics for each goop layer
  (`GXReadPixMetric`); and
- EFB texture copies are written back to main memory.

The port answers peeks and pixel metrics from the previous frame's
asynchronous readback, falling back to a synchronous read only when a group is
new, and writes copies back through fenced pixel buffers.

Dolphin's built-in `GMS.ini` turns on the expensive paths for this game:
`EFBAccessEnable = True`, `EFBToTextureEnable = False` (copies go to RAM) and
`PerfQueriesEnable = True`. In the pinned Metal backend,
`PerfQuery::FlushResults` blocks on a condition variable until the GPU
returns results, and EFB peeks that miss the tile cache trigger a readback.
SunPad runs the CPU and GPU on one host thread, so each wait stalls the game.
Its size on SunPad is unmeasured.

### 4. Save files are written in place

The port writes each memory-card file to `.tmp` and renames it, and repairs a
cut-short file on load so Sunshine's two internal copies can recover. It fixed
"The device in Slot A is not supported" this way.

SunPad uses Dolphin's GCI folder. In the pinned runtime,
`GCMemcardDirectory::FlushToFile` opens each dirty save with `"wb"`
(truncate) and writes it in place. On load, any GCI whose size does not match
its header is skipped without a message. An iOS termination or crash during a
write can therefore make a save disappear from the game's view. SunPad's
lifecycle code gives the one-second flush thread a two-second background
grace window, which narrows but does not close that window.

### 5. A real 60 FPS needs more than a frame-rate switch

The port's 60/120 FPS mode reports the new rate through
`SMSGetVSyncTimesPerSec` and keeps movement on 120 Hz ticks. It then needed
35 more `framerate-*` patches for objects that count frames instead of time:
wipes, gates, console timers, flocks, grass and flag sway, ferris wheel and
coaster rates, boss timers, ripples, smoke, particles and sound frame work.

SunPad's 60 FPS Patch is a six-line Gecko code. It sustained near-60 FPS at
real-time speed on a physical iPad but was judged unusable in hands-on play,
and the exact symptoms were not recorded
([TECH-DEBT](TECH-DEBT.md#unresolved)). Objects running at twice their intended
rate would match that verdict. This is an inference until the scene matrix
classifies the failures, but the port's patch list is a map of where to look.

### 6. Measurement and regression tooling worth copying in spirit

- A debug overlay splits each frame into game code, vertex loading, draw
  batches, textures, EFB copies, peeks, GPU wait, present and idle time.
  SunPad's P0 diagnostics list asks for the same split.
- `SMS_WARP=stage,scenario` jumps from file select to a named area, and
  scripted or `.dtm` input replays a route. `tools/regress` hashes frames
  and audio for title, plaza and frame-rate gate runs. SunPad's research names
  a repeatable route as the missing prerequisite for device comparisons.
- The vertex loader keeps one reader per attribute, chosen once per
  primitive, and a packed format per VAT, rebuilt only when the VAT changes.
  That cut vertex loading from 10.6 to 4.7 ms per frame in their Delfino Plaza
  run on x86. It is evidence that specialized, non-JIT loaders pay off, which
  is SunPad's rank 4 item.

### 7. HD texture packs use Dolphin's format

The port loads packs in Dolphin's custom-texture format. The UHD pack it
installs is a 986 MB download; the same project publishes a 156 MB 1080p
variant. SunPad's pinned runtime already contains Dolphin's
`HiresTextures` loader and `GFX_HIRES_TEXTURES` setting, but SunPad exposes
no texture-pack path.

### 8. Widescreen details

The port widens the game camera with a game patch, keeps the HUD 4:3 in the
centre by default, makes the screen fader full width, and can anchor HUD
panes to the screen edges. SunPad's experimental 16:9 uses Dolphin's GMSE01
widescreen code; these details are a checklist for its remaining defects.

## Findings that do not transfer

- Endian converters, OS/thread emulation, DVD and ARAM emulation, and the
  host DSP mixer replace hardware that SunPad's runtime already emulates.
- Decompilation fixes (return values, case scoping, bounds patches) correct
  the decompiled source, not the retail program SunPad runs.
- 64-bit pointer work and x86 floating-point parity work target x86 hosts.
- HD movie replacement depends on the port's own THP player.

## Where SunPad is ahead

SunPad runs the retail program, so its game logic matches the console except
where the runtime is wrong. It runs natively on Apple silicon, iPhone and iPad,
with Metal, touch controls, controller mapping, Files import and diagnostics.
The decompilation route would trade that for speed and moddability, and would
need the arm64 and Metal work above before it could reach an iPhone.

## Use and attribution boundary

- No sms-pc-port source, patch or asset is copied into SunPad or its forks.
- Behavior is re-derived from the CC0 decompilation, Dolphin, and SunPad's own
  measurements. Documented findings are cited to the port.
- The decompilation's symbol map may become a pinned, hash-checked build input
  under its CC0 terms. It is not committed to this repository.
- Asking the port's author about a license is optional and only matters if
  code reuse is ever proposed.
