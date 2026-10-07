# Dependencies

Updated September 14, 2026.

## Maintained source graph

SunPad now consumes maintained forks with upstream history and exact gitlinks.
Normal bootstrap applies no patches. The lanes intentionally retain their own
source snapshots so tvOS surround audio does not replace the iOS audio path.
DolRecomp remains at the same reviewed upstream commit, available in the maintained
fork. No Galaxy-specific compiler optimization, Wii control policy, THP experiment
or audio implementation is imported by this migration.

| Lane | Component | Gitlink / checkout | Selected commit |
| --- | --- | --- | --- |
| apple | [ModernGekko](https://github.com/chrissotraidis/ModernGekko) | `ref/ModernGekko` | `8f49c550ae4637b8b05bc1c2d3cbd2301bd969e9` |
| apple | [RecompCore](https://github.com/chrissotraidis/RecompCore) | `ref/ModernGekko/vendor/dolphin` | `da96175d5389b11f6c5f1eb8d680d437a71aab15` |
| apple | [DolRecomp](https://github.com/chrissotraidis/DolRecomp) | `ref/ModernGekko/vendor/dolphin/DolRecomp` | `fa0cf619e8d7eb8cba7eaf55267a12caaebb46aa` |
| tvos | [ModernGekko](https://github.com/chrissotraidis/ModernGekko) | `ref/ModernGekko-tvOS` | `3982ff05bef91d9e87acd7ebdb3f3b058c53e7f8` |
| tvos | [RecompCore](https://github.com/chrissotraidis/RecompCore) | `ref/ModernGekko-tvOS/vendor/dolphin` | `6e8c569c4c579328907c5c12c0e63e07fd643df1` |
| tvos | [DolRecomp](https://github.com/chrissotraidis/DolRecomp) | `ref/ModernGekko-tvOS/vendor/dolphin/DolRecomp` | `fa0cf619e8d7eb8cba7eaf55267a12caaebb46aa` |
| shared | [ModernGekko-Template](https://github.com/ExpansionPak/ModernGekko-Template) | `ref/ModernGekko-Template` | `1ee85bb5e09c38f493a09f5fa6e9dc8228b23e42` |

Each ModernGekko checkout pins RecompCore at `vendor/dolphin`, which pins
DolRecomp. The template is a third root submodule. Runtime/compiler origins are
[ModernGekko](https://github.com/ExpansionPak/ModernGekko),
[RecompCore](https://github.com/ExpansionPak/RecompCore), and
[DolRecomp](https://github.com/ExpansionPak/DolRecomp). See [credits](../CREDITS.md).

The [dependency lock](../config/dependencies.lock.json) records upstream bases and
URLs. The [migration record](../config/dependency-migration.json) maps historical
patch hashes to fork commits. Historical patches remain for older release and
external donor references, not as a second maintained build path.

## Preparing sources

```sh
./scripts/bootstrap-dependencies.sh --sources-only
./scripts/check-repository.sh
```

Omit `--sources-only` to initialize the required Apple build externals. The verifier
checks URLs, gitlinks, checkout commits and tracked/nonignored modifications,
including nested dependencies. Ignored game/build inputs are outside this check.
A `.git` metadata file, as used by submodules/worktrees, is supported.

Older workspaces have modified standalone clones in `ref/`. Bootstrap refuses to
overwrite them. Use a fresh checkout or worktree for migration, preserving private
images, generated modules and saves in the old workspace. Do not run a recursive
reset or clean. The tvOS default is now `ref/ModernGekko-tvOS`, not the older
`build/tvos-deps/ModernGekko` patch-replay tree.

## Updating dependencies and releases

Commit runtime changes to the appropriate maintained fork, update its parent's
nested gitlink, then update the app gitlink and lock. Use full SHAs, not branch tips.
Run source checks and clean Apple runtime/host builds. Preserve original licenses,
notices and author credit. See [contribution policy](../CONTRIBUTING.md).

The packagers bundle credits, original dependency license texts and source
references. Those references describe the packaging checkout, not proof that an
externally supplied binary was built from it. Release promotion also needs frozen
build inputs, generated-module identity, toolchain/flags and artifact hashes.
Older public IPAs retain their own source and device-evidence limitations.

## Historical baseline and research inventory

### Research references (not build inputs)

| Reference | Revision reviewed | License | Use |
|---|---|---|---|
| [sms-pc-port](https://github.com/chasem-dev/sms-pc-port) | `89e9fd01602bfa9735cdb1d5713d39edff91d9e7` | none declared | Research only; no code used ([review](SMS-PC-PORT-REVIEW.md)) |
| [sms-english](https://github.com/chasem-dev/sms-english) `config/GMSE01/symbols.txt` | `d5f4eb3eb54ac49638b5513efb1fc368068805da` (file SHA-256 `c75a8f35c1d51e7978cc66aeaa86c1d4e2d16c5603576183e0cd49e66a8d98ff`) | CC0-1.0 | Planned hash-checked input for profiling and native replacements ([plan](IMPROVEMENT-PLAN.md#pass-2-measurement)) |

If the symbol map becomes a build input, pin its commit and hash in
`config/dependencies.lock.json` and verify it against the extracted
`main.dol` before use.

### Original records

The following records predate the fork migration. They describe the original
upstream bases and research setup, not current pins or current host versions.

## Host toolchain (verified on this machine)

| Tool | Version / path | Purpose |
|---|---|---|
| macOS | 26.5 (25F71) | Host OS |
| Architecture | arm64 Apple Silicon | Required product architecture |
| Xcode | 26.6 (17F113) | AppleClang, SDKs, simulators |
| AppleClang | 21.0.0.21000101 | C/C++ compiler |
| CMake | 3.27.1 (`/opt/homebrew/bin/cmake`) | Build system |
| Ninja | present (`/opt/homebrew/bin/ninja`) | Generator/build backend |
| Git | 2.41.0 | Source control / submodules |
| Python 3 | 3.11.10 | Scripts, decomp tooling |
| gh | present | Repository research |

## External repositories (pinned)

| Component | URL | Local path | Pinned revision | License | Purpose |
|---|---|---|---|---|---|
| ModernGekko | https://github.com/ExpansionPak/ModernGekko | `ref/ModernGekko` | `0514d9f03f8602809f66fc92fdca87d30e752997` | GPL-3.0 | GameCube/Wii recomp runtime (Dolphin-derived) |
| ModernGekko vendor dolphin/RecompCore branch | https://github.com/ExpansionPak/RecompCore (`moderngekko-vendor`) | `ref/ModernGekko/vendor/dolphin` | `13e492094902644b0d113c586300d358640f9e19` | Dolphin-derived / mixed | Vendored runtime core used by ModernGekko |
| ModernGekko-Template | https://github.com/ExpansionPak/ModernGekko-Template | `ref/ModernGekko-Template` | `1ee85bb5e09c38f493a09f5fa6e9dc8228b23e42` | none declared in GitHub metadata | Reproducible extract/recompile/run Makefile pipeline |
| DolRecomp | https://github.com/ExpansionPak/DolRecomp | `ref/ModernGekko/vendor/dolphin/DolRecomp` | `fa0cf619e8d7eb8cba7eaf55267a12caaebb46aa` | GPL-3.0 | Recursively pinned static PowerPC recompiler (DOL → C/LLVM); fixes Gekko float-pipeline state and emits the inlined hot-helper ABI |
| RecompCore (top-level clone) | https://github.com/ExpansionPak/RecompCore | `ref/RecompCore` | `af7a1a4854ee243b92926875e5a6b66663b0fda0` | NOASSERTION / Dolphin-derived | Upstream continuation referenced by ModernGekko |
| Super Mario Sunshine decomp | https://github.com/doldecomp/sms | `ref/sms` | `5a8c71edd157a73e09cf62d7faaa3821feaf9913` | CC0-1.0 (project scaffolding; no assets) | Matching decompilation reference; **not** SunPad’s runtime path |
| StrikersRecomp | https://github.com/aharonahdoot/StrikersRecomp | `ref/StrikersRecomp` | `cd88f71f5a836c103484c038454b4143000d883c` | GPL-3.0 | Worked example of DolRecomp + runtime packaging for another GameCube title |
| BellPad | https://github.com/chrissotraidis/bellpad | `ref/bellpad` | local checkout | project license in tree | Apple platform UX/integration reference for Animal Crossing |

## Local non-redistributable materials

| Material | Local path | Notes |
|---|---|---|
| Super Mario Sunshine USA ISO | `ref/Super Mario Sunshine.iso` | User-supplied; never commit/publish |
| BellPad nested build trees / retail AC image (if present inside bellpad) | under `ref/bellpad` | Reference only; do not republish game data |

## Smallest coherent dependency set selected for Stage 1

Required now:

1. **DolRecomp** — generate portable C (or later LLVM objects) from `main.dol`.
2. **ModernGekko** (+ vendored dolphin/RecompCore branch and required Externals) — host runtime, module packaging, launch.
3. **ModernGekko-Template** — orchestrates extract → recompile → module → run.

Useful but secondary:

- **doldecomp/sms** — symbols/maps/progress for research; not a playable native path by itself.
- **StrikersRecomp** — packaging and game-specific HLE patterns as an analogy.
- **BellPad** — Apple app structure for Stages 2–4.

Not selected as primary runtime:

- Standalone generic Dolphin JIT frontend as the product.
- Incomplete matching decompilation as the sole executable core.

## Build requirements implied by upstream

- C11 / C++23 toolchain (AppleClang verified for template compiler check).
- CMake + Ninja + pkg-config + Git + Python.
- ModernGekko dolphin vendor Externals for SDL, zlib-ng, libspng, VMA, cubeb, SPIRV-Cross, libusb (initialized locally as needed).
- No game data is downloaded by these repositories.

## iOS Simulator build requirements (SunPad)

- Xcode 26.x with the iOS 26.x Simulator SDK.
- The vendored `fmt`, `lz4`, and `zstd` sources. The iOS core build compiles
  the required static libraries in its own ignored build tree;
  they do not consume unexplained prebuilt libraries from `/tmp`.
- The iOS toolchain file lives at `scripts/ios-simulator-toolchain.cmake`.
