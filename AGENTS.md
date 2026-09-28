# Working on SunPad

## Releases paused

No public releases until this repo is marked Clear in the maintainer's private release audit. Do not publish, re-publish, or restore any release, IPA, APK, or macOS build, and do not add download links, until then.

Before any future public release, every artifact must pass `python3 ~/.codex/release-gate/release_gate.py <artifact>` on the maintainer's machine. A failure is a stop, not a note.

Keep changes simple and consistent with the application. Be careful when changing
button wiring and recheck the affected flows. Do not suggest Figma.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before implementation. Maintain runtime and
compiler changes in their forks, preserve upstream history and attribution, and
update pinned gitlinks and the dependency lock together. Do not restore a production
patch-replay workflow or discard modified dependency checkouts.

Run the source suite and applicable clean builds. Record exact artifact and device
evidence separately. Preserve user data, signing state and concurrent work.
