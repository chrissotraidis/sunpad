# Research

Last updated: 2026-08-05

## Questions this document answers

1. What public Super Mario Sunshine recompilation evidence exists?
2. What is ReShine, and what can be reproduced from public sources?
3. How do ModernGekko, DolRecomp, RecompCore, and doldecomp/sms relate?
4. What is the smallest viable path to native host execution?

## Ecosystem map

### DolRecomp (ExpansionPak)

Static recompiler for GameCube/Wii (and experimental Wii U Espresso) CPU code.

- Reads DOL/REL/RPX.
- Decodes a large Gekko/Broadway opcode set (README claims 236 recognized opcodes).
- Emits split portable C, optionally LLVM objects.
- Includes native GameCube ISO extraction.
- Does **not** include a full game runtime.

### ModernGekko (ExpansionPak)

Runtime for GameCube/Wii recomps, built on a Dolphin-derived core.

- Provides `moderngekko-port` (module packaging/cache) and `moderngekko-run` (launcher).
- Loads recompiled game modules as native shared libraries.
- Includes NoGUI-style frontend pieces, graphics/audio/HLE services, controller config via Dolphin-style ini files.
- Hall of Fame credits **binsento** for Super Mario Sunshine and Brawl recomps.

### ModernGekko-Template (ExpansionPak)

Makefile-driven pipeline:

`ISO → extract → recompile main.dol → compile host module → run`

This is the intended Stage 1 reproduction harness for SunPad.

### RecompCore (ExpansionPak / aharonahdoot lineage)

Dolphin-derived recompilation CPU-core / chassis work. ModernGekko vendors a `moderngekko-vendor` branch of RecompCore as `vendor/dolphin`. There is also an older aharonahdoot/RecompCore description focused on static recompilation with interpreter fallback.

### StrikersRecomp (aharonahdoot)

Public worked example for Super Mario Strikers (`G4QE01`):

- DolRecomp generation of ~665k instructions, zero unknown opcodes.
- Game-specific HLE/MMIO policy and packaging.
- Demonstrates both RecompCore module loading and a standalone GXRuntime path.

Useful as process evidence, not Sunshine logic.

### doldecomp/sms

Matching decompilation project for Super Mario Sunshine.

- Supported versions documented as `GMSJ01` primarily; PAL noted as broken; US `GMSE01` is **not** listed as a current default supported configure target in the README snapshot inspected.
- Progress service reports substantial but incomplete code matching (fuzzy match around low-70% range at pin time).
- Produces matching object files for analysis, **not** a host-native playable recompilation product.

### ReShine

Public search results:

- No authentic public Super Mario Sunshine “ReShine” source repository was found.
- Unrelated repositories reuse the name “Reshine/ReShine”.
- The only concrete public pointer is ModernGekko’s Hall of Fame credit for a Sunshine recomp by binsento.

Conclusion for SunPad planning:

- Treat ReShine as **non-public / community-reported**.
- Do not depend on private patches that cannot be inspected.
- Reproduce from public DolRecomp + ModernGekko first.
- Implement the **minimum Sunshine-specific deltas** only when generic tools fail, and document each delta separately.

## Terminology discipline

| Term | Meaning in this project |
|---|---|
| Matching decompilation | Recovering C/C++ that compiles back to the original objects/instructions for analysis |
| Static recompilation / AOT recomp | Translating guest machine code to host-native code ahead of time |
| Generated host code | Local DolRecomp output derived from a user disc; not redistributed |
| Compatibility runtime / HLE services | Host replacements for GameCube hardware/OS services (GX, audio, disc, PAD, etc.) |
| Emulation-derived runtime | Dolphin-lineage components still providing hardware/OS behavior |
| JIT | Runtime translation of guest code; forbidden on iOS/iPadOS, and allowed only as fallback outside covered AOT regions on macOS |

## Selected Stage 1 path

1. Use local `GMSE01` Rev 0 ISO.
2. Build DolRecomp + ModernGekko via ModernGekko-Template.
3. Extract disc and recompile `main.dol` with portable C backend first.
4. Package module with `moderngekko-port`.
5. Launch with `moderngekko-run` and capture logs.
6. Measure: unknown opcodes, boot progress, title screen, input, plaza load, objective, save/reload.
7. Only then implement Sunshine-specific runtime fixes if needed.

## Why not decomp-first?

`doldecomp/sms` is incomplete and currently oriented around matching, especially JPN. It is invaluable for symbols and understanding, but it is not yet a complete native game implementation for SunPad’s product targets. Static recompilation can produce a full CPU module from the retail DOL immediately, then rely on the compatibility runtime for hardware services.

## Legal / provenance research notes

- No copyrighted disc image, extracted assets, or generated game-derived modules will be committed.
- Public docs must not claim “not emulation” without naming the Dolphin-derived compatibility runtime components that remain.
- User must supply a legally obtained disc image.

## Open research items

- Exact public availability of any Sunshine-specific address maps, code-patch ranges, or runtime patches used by private recomps.
- Whether GMSE01 needs REL modules beyond `main.dol`.
- Whether ModernGekko’s default HLE/GX path is sufficient for Sunshine’s particle/water/FLUDD-heavy scenes.
- Controller analog-trigger and rumble behavior under ModernGekko on macOS.
