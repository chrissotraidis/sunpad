# Contributing to SunPad

Keep changes simple and explain the concrete problem they solve. Recheck any
controls or navigation you change. Preserve upstream names, licenses, authorship,
game data, saves, settings, signing identities and concurrent work.

Runtime changes belong in the maintained ModernGekko/RecompCore forks. Compiler
changes belong in DolRecomp. Use reviewable commits and update full SHA pins,
gitlinks and the dependency guide together. The Apple and tvOS lanes deliberately
retain different audio implementations. Do not replace either with GalaxyPad's
runtime or silently reset an existing modified checkout.

Research references are not code sources. Do not copy code, patches or assets
from [sms-pc-port](https://github.com/chasem-dev/sms-pc-port); it has no license.
Re-derive behavior from the CC0 GMSE01 decompilation, Dolphin and SunPad's own
measurements, and cite the finding that led to the change. Follow the ground
rules in the [improvement plan](docs/IMPROVEMENT-PLAN.md#ground-rules).

For behavioral fixes, reproduce the failure and add a focused regression where
feasible. Run `scripts/bootstrap-dependencies.sh --sources-only` followed by
`scripts/check-repository.sh`. Runtime/API changes also need a clean Apple runtime
and host build. CI builds both the iOS and tvOS Simulator lanes without game data.
Private generated-module and physical-gameplay validation are separate gates.
Experiments stay opt-in until justified by measured correctness and hardware tests.

New releases must record the app commit, recursive dependency commits, toolchain,
SDK, flags, exact generated-module inputs and artifact hashes. Retain corresponding
redistributable source and original notices with reproduction instructions.
Packaging source references alone do not prove an externally supplied binary's
provenance. Describe missing historical evidence honestly.

AI-assisted changes receive the same review and validation. Follow the receiving
project's contribution policy before submitting upstream. Never attach game
images, extracted assets, saves, generated modules, credentials or signing material
to an issue or pull request. A build or synthetic test is not physical gameplay,
audio, full-game or minimum-device acceptance.

By contributing, you agree that your contribution is licensed under the
repository's GPL-3.0-or-later license. Review diagnostic logs for personal paths
and unnecessary device details before sharing them.
