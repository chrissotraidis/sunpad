# Third-party notices

SunPad's own integration source is licensed under the GNU General Public
License, version 3 or later. The project builds against separately cloned,
pinned maintained forks of upstream repositories; their source and license files remain in those
checkouts and are not vendored into this repository.

The exact Apple/tvOS commits, original upstream bases and repository URLs are
recorded in [the dependency lock](config/dependencies.lock.json). ModernGekko and
DolRecomp retain their GPL notices. RecompCore retains Dolphin's per-file SPDX
terms and third-party licenses. The template retains its original notices.
[CREDITS.md](CREDITS.md) identifies the projects and contributor roles.

See [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) for URLs, purposes, and the
complete dependency inventory. A distributed binary that incorporates the
GPL-covered runtime must be accompanied by the corresponding source and the
applicable license notices as required by those licenses.

## Decompilation engine

The decompilation engine ([plan](docs/DECOMP-ENGINE-PLAN.md)) is built from the
pinned [sms-pc-port fork](https://github.com/chrissotraidis/sms-pc-port) and its
submodules. Each keeps its license file in its own checkout.

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
| MoltenVK 1.4.2 | Apache-2.0 | Fetched and checked by `scripts/fetch-moltenvk.sh` into `ref/moltenvk` |

The engine's compiled code comes from decompiled game code. It is built on the
player's own computer and is never published.

Super Mario Sunshine, Nintendo, and GameCube names, game imagery, and
screenshots are owned by their respective rights holders. They are not
licensed under the GPL and are used here only to identify compatibility and
document runtime behavior. No retail image, extracted asset or save is included. The source repository
excludes generated game modules. Published preview IPAs include the required
GMSE01 AOT executable module. That distinction does not license Nintendo material
under SunPad's GPL license.

The SunPad icon is a project-specific AI-generated image. Its provenance is
recorded beside the asset in
[`apple/ios/Assets.xcassets/AppIcon.appiconset/PROVENANCE.md`](apple/ios/Assets.xcassets/AppIcon.appiconset/PROVENANCE.md).
