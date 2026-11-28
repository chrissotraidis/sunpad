# Third-party notices

SunPad's own source is licensed under the GNU General Public License, version
3 or later. Its dependencies are pinned Git submodules and a checked download.
They keep their own licenses in their own checkouts and aren't vendored into
this repository. [CREDITS.md](CREDITS.md) names the projects and their roles,
and [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) the exact pins.

## In the published app

| Component | License | Where |
| --- | --- | --- |
| SunPad | GPL-3.0-or-later | [LICENSE](LICENSE) |
| MoltenVK 1.4.2 (Khronos Group and contributors), linked statically | Apache-2.0 | `SourceNotices/licenses/MoltenVK/LICENSE` in the app, fetched by `scripts/fetch-moltenvk.sh` |

The app also carries `SourceNotices`, made by `scripts/package-notices.sh`,
with the source references and license texts of every dependency initialized
in the checkout that packaged it.

## In the engine a player's Mac builds

The engine is built from the [sms-pc-port fork](https://github.com/chrissotraidis/sms-pc-port)
and its submodules. It is compiled from decompiled game code, built on the
player's own computer and never published.

| Component | License | Where |
| --- | --- | --- |
| sms-pc-port (SoftwareAura LLC and contributors) | MIT | `ref/sms-pc-port/LICENSE` |
| sms-english and doldecomp/sms decompilation | CC0-1.0 | `ref/sms-pc-port/decomp/LICENSE` |
| sms-mod-sdk header (SoftwareAura LLC) | MIT | `ref/sms-pc-port/sdk/LICENSE` |
| stb_image, stb_image_write, stb_truetype, stb_easy_font | Public domain or MIT | `ref/sms-pc-port/platform/gx/src/third_party` |
| bcdec | MIT | the same folder |
| Inter font (glyphs in `inter_ascii.h`) | SIL Open Font License 1.1 | `Inter-LICENSE.txt` in the same folder |
| Khronos OpenGL and KHR headers | MIT | `ref/sms-pc-port/platform/gx/third_party` |
| Vulkan-Headers 1.3.296 | Apache-2.0 or MIT | Downloaded and checked by SHA-256 at configure time |
| volk 1.3.296.0 | MIT | the same |
| VulkanMemoryAllocator 3.1.0 | MIT | the same |
| glslang 15.0.0 | BSD-3-Clause and the others listed in its LICENSE.txt | the same |

## The legacy engine

SunPad 0.3.x and earlier included GPL-licensed, Dolphin-derived components
(ModernGekko, RecompCore, DolRecomp and ModernGekko-Template). Their notices
are in [THIRD_PARTY_NOTICES.md at legacy-engine-final](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/THIRD_PARTY_NOTICES.md).
SunPad 0.4.0 contains none of them.

## Game and artwork

Super Mario Sunshine, Nintendo and GameCube names, game imagery and
screenshots belong to their rights holders. They aren't licensed under the
GPL and are used here only to identify compatibility and document behavior.
No retail image, extracted asset or save is included anywhere.

The SunPad icon is a project-specific AI-generated image. Its provenance is
recorded beside the asset in
[`apple/ios/Assets.xcassets/AppIcon.appiconset/PROVENANCE.md`](apple/ios/Assets.xcassets/AppIcon.appiconset/PROVENANCE.md).
