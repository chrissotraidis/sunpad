# Dependencies

Updated 28 November 2026, for SunPad 0.4.0.

SunPad's engine is a maintained fork of sms-pc-port, pinned as a Git submodule
with its two nested submodules. The app links MoltenVK, fetched from Khronos'
release and checked by hash. Nothing else is fetched, and no patches are
applied at build time. The [dependency lock](../config/dependencies.lock.json)
records each pin, and `scripts/dependency-lock.py` checks the checkouts
against it.

The legacy engine's dependencies (ModernGekko, RecompCore, DolRecomp and
ModernGekko-Template) are recorded in the
[legacy engine record](LEGACY-ENGINE.md#source-graph).

## Engine sources

| Component | Path | Pinned commit | License | Contents |
| --- | --- | --- | --- | --- |
| [sms-pc-port](https://github.com/chrissotraidis/sms-pc-port), branch `sunpad` | `ref/sms-pc-port` | `bd9936f23d545a8ce2ef857ea7de9ad6c6d8197d` | MIT | The port's platform layer (renderer, audio, card, disc, pad, OS services) and the embedded build SunPad loads |
| [sms-english](https://github.com/chasem-dev/sms-english) | `ref/sms-pc-port/decomp` | `967436b8c623834d38a57d34923775f45eca8861` | CC0-1.0 | The Super Mario Sunshine decompilation the engine compiles, from [doldecomp/sms](https://github.com/doldecomp/sms) |
| [sms-mod-sdk](https://github.com/chasem-dev/sms-mod-sdk) | `ref/sms-pc-port/sdk` | `67322b0c2cf9543847745e350f911018f13561f7` | MIT | The port's mod interface headers |

The fork's upstream is [chasem-dev/sms-pc-port](https://github.com/chasem-dev/sms-pc-port)
at `20abb7e8c2a882670c9e7bb08687cc336a9d62b9` (22 November 2026). The nested
pins are the ones upstream uses at that commit. The fork adds ten commits on
`sunpad`, oldest first:

| Commit | Change |
| --- | --- |
| `a47eb3f` | `SMS_EMBED`: builds the game as `libsms_embed.dylib` with the C interface in `platform/embed/sms_embed.h` |
| `898e20e` | Draws without base vertices on the iOS and tvOS Simulators |
| `9c66e0d` | A weak default for `port_host_pad_read` |
| `b3ddbc3` | No SDL search in the embedded build, and scripted input through the port's own path |
| `26b58ac` | Render scale set by the app, applied at the next frame |
| `8b900f1` | Device builds for iPhone, iPad and Apple TV, with game memory at `0x7000000000` |
| `9ea11ac` | tvOS builds without the crash symbolizer process or the alternate signal stack |
| `80573d7` | `SMS_RETAIL_UI`: the pause menu and movies as the retail game shows them |
| `043db83` | `SMS_RETAIL_UI` keeps `SMS_SKIP_INTRO` and placeholder movies |
| `bd9936f` | `SMS_VK_ASYNC_PIPELINES`: new Vulkan pipelines are made in the background |

Each change is written so it can be offered upstream. None has been sent
without the maintainer's decision.

## MoltenVK

`scripts/fetch-moltenvk.sh` downloads
[MoltenVK 1.4.2](https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.2)
(`MoltenVK-all.tar`, SHA-256
`562a15a29bc358446a56a4091c5f7e08f604184187c1d34f712148b61ef17276`) into
`ref/moltenvk`. The SunPad target links its static `MoltenVK.xcframework`,
so the published app already contains MoltenVK and its Apache-2.0 license
(`SourceNotices/licenses/MoltenVK/LICENSE`). A player's Mac doesn't fetch it:
`package-ios.sh` reuses the license from the published app when
`ref/moltenvk` is absent.

## Build tools

| Tool | Checked with | Used for |
| --- | --- | --- |
| Apple silicon Mac | M3 Max, macOS 27.2.1 | Every build |
| Xcode with the iOS platform | 27.2 (27B52) | The app, the iOS SDK, signing tools |
| [Homebrew](https://brew.sh) LLVM | Clang 22.1.8 (`/opt/homebrew/opt/llvm`) | The engine. Its game code needs the `gameptr` pass plugin, which Apple's Clang can't load. `SUNPAD_LLVM` names another LLVM |
| CMake | 4.4.2 | The engine build |
| Ninja | 1.13.2 | The engine build |
| Git, Python 3 | Apple's `/usr/bin/python3` 3.9.6 | Sources, scripts and checks |

Players install the tools Xcode doesn't provide with `brew install cmake ninja
llvm`.

## Preparing sources

```sh
./scripts/bootstrap-dependencies.sh                 # engine sources and MoltenVK
./scripts/bootstrap-dependencies.sh --sources-only  # engine sources only (PadMint)
python3 scripts/dependency-lock.py
```

Bootstrap checks every existing checkout first and refuses to overwrite one
with local changes. `dependency-lock.py` checks URLs, gitlinks, checkout
commits and tracked or nonignored changes, including the nested submodules.

The disc image is never a build input. Players import it in the app.

## Updating the engine

1. Commit the change in the fork on `sunpad` and push it.
2. Update the gitlink `ref/sms-pc-port` and `config/dependencies.lock.json`
   together, with full SHAs. Change the nested pins only when the fork's
   commit changes them.
3. Run `python3 scripts/dependency-lock.py`, `scripts/check-repository.sh`,
   `scripts/build-engine.sh` for `iphoneos` and `iphonesimulator`, and a route
   with `scripts/run-engine-route.sh`.
4. Keep upstream history, licenses and author credit. See the
   [contribution policy](../CONTRIBUTING.md).

To take a newer upstream, merge `chasem-dev/sms-pc-port` into `sunpad`,
resolve conflicts in the fork, and update `upstreamRevision` in the lock with
the pin.

## Release packages

The published app contains no engine and no game code. `package-ios.sh`
bundles SunPad's license, `THIRD_PARTY_NOTICES.md`, the install guide, and
`SourceNotices` with the source references and license texts of every
initialized dependency (`scripts/package-notices.sh`). Those references name
the checkout that made the package. They don't prove where a separately
supplied engine came from.
