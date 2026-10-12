# Working on SunPad

## Further releases paused

The maintainer separately approved v0.2.1, published on 4 October 2026.
That approval does not clear the wider private release audit or authorize a
future release. Preserve the approved release and keep its support documentation
accurate. Do not publish, re-publish, or restore another release, IPA, APK, or
macOS build, or add new download links, until this repository is marked Clear
in the private audit or the maintainer explicitly approves that exact release.

Before any future public release, every artifact must pass `python3 ~/.codex/release-gate/release_gate.py <artifact>` on the maintainer's machine. A failure is a stop, not a note.

Keep changes simple and consistent with the application. Be careful when changing
button wiring and recheck the affected flows. Do not suggest Figma.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before implementation. Maintain runtime and
compiler changes in their forks, preserve upstream history and attribution, and
update pinned gitlinks and the dependency lock together. Do not restore a production
patch-replay workflow or discard modified dependency checkouts.

Run the source suite and applicable clean builds. Record exact artifact and device
evidence separately. Preserve user data, signing state and concurrent work.

## Improvement plan

Ongoing engineering work is organized in
[docs/IMPROVEMENT-PLAN.md](docs/IMPROVEMENT-PLAN.md). When asked to continue that
plan, to improve performance or save safety, or to pick up SunPad work without a
more specific request, start at its "Start here" section and follow its goal
loop. Record every session in [docs/IMPROVEMENT-LOG.md](docs/IMPROVEMENT-LOG.md).
[sms-pc-port](https://github.com/chasem-dev/sms-pc-port) is a research
reference only; do not copy its code.

To compare SunPad with another Sunshine project or look for features to learn
from, follow [docs/RESEARCH-LOOP.md](docs/RESEARCH-LOOP.md). Its source rules
say what may be read and what may be reused.
