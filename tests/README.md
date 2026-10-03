# Tests

SunPad treats runtime evidence as the source of truth: a successful compile is
not gameplay success. Dated checklists, commands, screenshots, and remaining
defects live in [docs/TESTING.md](../docs/TESTING.md), and the harness scripts
live in [scripts/](../scripts):

- `scripts/ios-build-core.sh` / `ios-provision.sh` — iOS core + module build
  and app provisioning.
- `scripts/gcpipe.py` — pipe-device input probes (PRESS/RELEASE, stick sets).
- `scripts/simdrag.swift` — posts real drags to the iOS Simulator for
  touch-control verification.
- `scripts/stage1-status.sh` / `stage1-run.sh` / `sunpad-capture.py` —
  desktop Stage 1 checks and capture helpers.

Run only one Simulator at a time on a given machine.

Focused source regression gates:

```sh
./tests/test-input-pipe-encoder.sh
./tests/test-controller-mapping.sh
./tests/test-controller-slots.sh
./tests/test-experimental-60fps-config.sh
./tests/test-diagnostics.sh
./tests/test-iphone-touch-layout-defaults.sh
./tests/test-game-data-setup.sh
./tests/test-macos-user-defaults.sh
```

Before publishing or merging release-hardening work, run the combined
repository gate from the repository root:

```sh
./scripts/check-repository.sh
```

It checks whitespace, shell/Python/plist/asset syntax, local Markdown links,
the focused tests, prohibited tracked artifacts, likely credential material,
personal absolute paths, and the required license/notice files. It does not
replace a clean-clone build or physical gameplay acceptance.
