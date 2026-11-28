# Working on SunPad

## Releases

Before any public release, every artifact must pass `python3 ~/.codex/release-gate/release_gate.py <artifact>` on the maintainer's machine. A failure is a stop, not a note.

Keep changes simple and consistent with the application. Be careful when changing
button wiring and recheck the affected flows. Do not suggest Figma.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before implementation. Engine changes go to
the maintained fork, with upstream history and attribution kept, and the gitlink
and dependency lock are updated together. Do not apply patches at build time or
discard modified dependency checkouts.

Run the source suite and applicable clean builds. Record exact artifact and device
evidence separately. Preserve user data, signing state and concurrent work.

## The engine

SunPad's only engine is built from the Super Mario Sunshine decompilation
through a maintained fork of [sms-pc-port](https://github.com/chasem-dev/sms-pc-port)
(MIT), branch `sunpad` ([architecture](docs/ARCHITECTURE.md),
[dependencies](docs/DEPENDENCIES.md)). Engine changes go to the fork with its
MIT notice and upstream history intact. `sms-iphone-ipad` and `sms-android`
have no license: read their documentation only and copy nothing from them.
Never publish an engine binary or an app that contains one.

Work after 0.4.0 is organized as task cards in
[docs/DECOMP-ENGINE-PLAN.md](docs/DECOMP-ENGINE-PLAN.md#follow-up-after-040). When
asked to pick up SunPad work without a more specific request, start there.
Record every session in [docs/IMPROVEMENT-LOG.md](docs/IMPROVEMENT-LOG.md).

The legacy engine (0.3.x) was removed in 0.4.0. Its record and how to bring it
back are in [docs/LEGACY-ENGINE.md](docs/LEGACY-ENGINE.md), and its last state is
the tag `legacy-engine-final`. Documents about it, such as
[docs/IMPROVEMENT-PLAN.md](docs/IMPROVEMENT-PLAN.md), are history.

To compare SunPad with another Sunshine project or look for features to learn
from, follow [docs/RESEARCH-LOOP.md](docs/RESEARCH-LOOP.md). Its source rules
say what may be read and what may be reused.
