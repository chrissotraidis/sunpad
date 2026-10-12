# SunPad upstream integration review

September 14, 2026. Baseline: SunPad `ec20f8d`. Reference: GalaxyPad's
[engineering review](https://github.com/chrissotraidis/galaxypad/blob/f4c719e2f1425d1af054fc6dff96855a562af33d/docs/UPSTREAM-REVIEW.md),
[README attribution change](https://github.com/chrissotraidis/galaxypad/commit/65f1ef5)
and recent Codex discussions about upstream criticism, maintenance and release
provenance. This document records engineering alignment, not a blanket legal or
full-game certification.

## Findings and disposition

| GalaxyPad concern | SunPad finding and action |
| --- | --- |
| Buried or unclear attribution | README linked the wrong DolRecomp repository and placed credits near the end. Corrected the link, put upstream roles and fork links above gameplay imagery, added contributor/AI provenance and strengthened contribution guidance. |
| Runtime changes maintained as a patch stack | Moved the existing Apple and tvOS source snapshots to separate branches in maintained forks, selected with root/nested submodules and full commit pins. Bootstrap no longer replays patches. Historical patches remain for older releases and downstream donor references. |
| Bootstrap checks changed paths rather than exact content | Replaced the whitelist with Git graph, revision and source-cleanliness checks. Modified tracked files, added nonignored source, wrong URLs/gitlinks and missing checkouts are rejected. Existing modified trees are preserved. `.git` files are supported. |
| Suspected ARM64 JIT defect | RecompCore PR #6 is already an ancestor of SunPad's pinned upstream base. No speculative backport. Another suspected bug still needs a specific issue/commit or reproduction. |
| Packaging overwrites outputs before validation | iOS/tvOS now reject existing output and paths inside input apps, audit the staged archive before publication, and use exclusive output creation to reject racing publishers. tvOS temporary staging is cleaned. |
| Wrong dylib accepted as a game module | iOS audit now requires `_staticrecomp_get_module`, matching the existing tvOS audit. This proves only the loader interface, not game-code identity or correctness. |
| Missing or inaccurate notices | Corrected the claim that previews contain no generated module. Packagers now include credits, source references and original initialized dependency license texts, including Mac packages. These records do not retroactively establish an old binary's source provenance. |
| Queued extraction callback lifetime | Inspected SunPad's actual extractor and ran it with synthetic DiscIO, a drained serial worker and delayed main callbacks under ASan/UBSan. The original source passed. GalaxyPad's failure was not reproduced here, so no speculative extractor repair was retained. |
| Diagnostic producer/filter mismatch | SunPad has a different diagnostics implementation. Its report includes current/previous logs and redacts local app paths. No equivalent promise to omit all input samples was established. Existing report tests remain; users must review reports before sharing. This is not a full privacy certification. |
| Unused GalaxyPad UI / private tests blocking public checks | Those exact files and fixture dependencies are absent. SunPad's checks now inspect actual pinned fork sources instead of falling back to patch text. |
| iOS audio implementation missing from source | Preserve SunPad's own committed snapshot. GalaxyPad's frozen Galaxy audio policy and pointer/Wii/THP work are not SunPad fixes. tvOS remains separately pinned to its existing surround/controller implementation. |
| Undefined project contribution / demand for cheats | Clarified that SunPad provides the Apple integration and Sunshine compatibility work. GMSE01 widescreen, heatwave restoration and optional 60 FPS experiments already exist. Original 30 FPS remains supported. Stability precedes additional gameplay features. |

## Source and JIT evidence

The [lock](../config/dependencies.lock.json) records exact fork commits and upstream
bases. The [migration record](../config/dependency-migration.json) maps all five
historical snapshots to source commits. Each lane preserves the corresponding
applied source tree. Deliberate graph-only changes select maintained RecompCore and
DolRecomp URLs and nested commits. Upstream history, licenses and contributor
notices remain intact. DolRecomp stays at `fa0cf619e8d7eb8cba7eaf55267a12caaebb46aa`.

The upstream [PR #6](https://github.com/ExpansionPak/RecompCore/pull/6) merge is
`202704caa71574c9a89a65c7e4f0d35cbb7e1399`. Ancestry check:

```sh
git -C ref/ModernGekko/vendor/dolphin merge-base --is-ancestor \
  202704caa71574c9a89a65c7e4f0d35cbb7e1399 \
  13e492094902644b0d113c586300d358640f9e19
```

SunPad uses interpreter fallback on iOS and ARM64 fallback JIT on Mac. GalaxyPad's
released-Mac disassembly evidence belongs to GalaxyPad, not SunPad. This pass does
not claim a new SunPad binary/runtime verification of that repair.

## Validation and remaining gates

Source setup uses the public maintained forks. Real Git fixtures exercise clean
sources, modified existing files, untracked additions, URL/gitlink mismatch,
missing checkouts and `.git` metadata files. Packaging fixtures cover protected
inputs, existing outputs and a competing publisher. The actual extractor is
compiled against synthetic DiscIO with ASan/UBSan; no game image is used.

CI requires source checks plus separate iOS/tvOS Simulator runtime and app builds.
The tvOS host-link fixture intentionally has no game-loader export and cannot pass
the release audit. These builds never install an app or access saves.

[Preview 13](PREVIEW-13.md) replaces the older iOS/tvOS downloads with fresh
builds from the pinned forks. Exact source, toolchain, input and artifact hashes
are recorded with that release. This does not retroactively prove the older
binaries' provenance. Recipient-signed in-place updates, full-game performance,
acoustic correctness, oldest-device acceptance and tvOS save durability remain
separate physical validation gates. tvOS state remains purgeable cache data
requiring backup.

## Completed local verification

At app source `518f706`, the full source suite passed. Both clean Simulator
runtime and host builds passed with Xcode 26.6 (17F113), Apple Clang 21.0.0.
Dependency sources remained clean after each build. This includes the tvOS Xcode
resource/header-path migration to its pinned fork. No application was installed.

The Apple/tvOS ModernGekko source trees and Apple/tvOS RecompCore source trees
exactly matched their reconstructed patch trees before graph-only commits.
Both production packagers rejected existing outputs and paths inside input apps,
preserving the input and pre-existing output sentinels. The real iOS IPA audit
rejected a compiled unrelated ARM64 library under the game-module filename.
Notices generation succeeded for all 57 initialized dependency checkouts.

The unchanged extractor also passed the delayed-main-callback ASan/UBSan harness.
This bounded synthetic result is deliberately recorded as non-reproduction of
GalaxyPad's failure, not proof of every import path.

## Later review: sms-pc-port (October 2026)

A separate [research review](SMS-PC-PORT-REVIEW.md) compared SunPad with the
decompilation-based [sms-pc-port](https://github.com/chasem-dev/sms-pc-port).
It found no SunPad defect that the port's code fixes directly, because the two
projects share no runtime. It did identify work for SunPad's own forks: atomic
GCI save writes in RecompCore, a safe form of DolRecomp's existing direct-call
path, and deferred GPU readbacks. Those changes follow this document's fork and
pinning rules and are scheduled in the [improvement plan](IMPROVEMENT-PLAN.md).
The port has no license, so none of its code is used.
