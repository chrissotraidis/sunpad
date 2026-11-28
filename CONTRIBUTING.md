# Contributing to SunPad

Keep changes simple and explain the concrete problem they solve. Recheck any
controls or navigation you change. Preserve upstream names, licenses, authorship,
game data, saves, settings, signing identities and concurrent work.

SunPad's engine comes from a maintained fork of
[sms-pc-port](https://github.com/chasem-dev/sms-pc-port), which is MIT licensed.
Keep its notice and history, and land engine changes in the fork, on its
`sunpad` branch, before updating the pin. Update the gitlink and
`config/dependencies.lock.json` together with full SHAs
([DEPENDENCIES.md](docs/DEPENDENCIES.md#updating-the-engine)). Never reset an
existing modified checkout. Projects without a license, such as
`sms-iphone-ipad` and `sms-android`, are research references only. Don't copy
their code, patches or assets.

For behavioral fixes, reproduce the failure and add a focused regression where
feasible. Run `scripts/bootstrap-dependencies.sh` followed by
`scripts/check-repository.sh`. Engine or interface changes also need
`scripts/build-engine.sh` for `iphoneos` and `iphonesimulator`, an app build,
and a route ([TESTING.md](docs/TESTING.md)). CI builds the published app and the
device engine without game data. Device gameplay is a separate check.
Experiments stay opt-in until measured correctness and device tests justify them.

Releases record the app commit, the engine pins, the toolchain and SDK, and the
artifact hashes, and keep the corresponding source and original notices with
reproduction steps. Packaged source references alone don't prove where a
separately built engine came from. Describe missing evidence honestly.

AI-assisted changes receive the same review and validation. Follow the receiving
project's contribution policy before submitting upstream. Never attach game
images, extracted files, saves, engine binaries, credentials or signing material
to an issue or pull request. A build or synthetic test isn't gameplay, audio,
full-game or minimum-device acceptance.

By contributing, you agree that your contribution is licensed under the
repository's GPL-3.0-or-later license. Review diagnostic logs for personal paths
and unnecessary device details before sharing them.
