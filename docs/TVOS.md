# Apple TV

Last updated: 28 November 2026, for SunPad 0.4.0.

SunPad 0.4.0 has no Apple TV app. The tvOS preview ran the legacy engine and
was removed with it. It is described in the
[legacy engine record](LEGACY-ENGINE.md#apple-tv-and-mac), with its install
guide and build steps in
[TVOS.md at legacy-engine-final](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/TVOS.md).
Existing preview installs keep working.

The new engine already builds for tvOS: `scripts/build-engine.sh appletvos`
and `appletvsimulator` make `libsms_embed.dylib` for tvOS 17 with game memory
at `0x7000000000`, and the fork leaves out the crash symbolizer process and
the alternate signal stack there. An Apple TV app on it is planned after 0.4.0
([DECOMP-ENGINE-PLAN.md](DECOMP-ENGINE-PLAN.md#follow-up-after-040)). It needs a tvOS
target around the engine host, the focus-driven setup and import, storage in
`Library/Caches` (tvOS may purge other local data), and checks on Apple TV
hardware.
