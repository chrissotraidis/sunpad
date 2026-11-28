# Credits and provenance

SunPad is an Apple app around other people's work. Their projects make it
possible.

## SunPad 0.4.0 and later

| Project | Contribution |
| --- | --- |
| [sms-pc-port: chasem-dev and contributors](https://github.com/chasem-dev/sms-pc-port) | The MIT-licensed native port whose platform layer, renderer, audio and services make up SunPad's engine, through the [maintained fork](https://github.com/chrissotraidis/sms-pc-port) |
| [sms-english: GMSE01 decompilation](https://github.com/chasem-dev/sms-english) | The CC0 GMSE01 decompiled source compiled into the engine |
| [doldecomp/sms](https://github.com/doldecomp/sms) | The Super Mario Sunshine decompilation that sms-english continues |
| [sms-mod-sdk](https://github.com/chasem-dev/sms-mod-sdk) | The port's mod interface headers |
| [MoltenVK: Khronos Group and contributors](https://github.com/KhronosGroup/MoltenVK) | Vulkan on Metal for the engine |
| [GalaxyPad](https://github.com/chrissotraidis/galaxypad) | Dependency-verification approach and shared engineering-review findings |

SunPad's work is the iPhone and iPad app: touch controls and their editor,
controller mapping and rumble, settings, game-data import, save migration and
transfer, diagnostics, packaging, the PadMint recipe, and the fork's embedded
build. It doesn't claim authorship of the decompilation or the port.

## SunPad 0.3.x and earlier

The legacy engine ([record](docs/LEGACY-ENGINE.md)) was built on:

| Project | Contribution |
| --- | --- |
| [ModernGekko: Hyperway, ExpansionPak and contributors](https://github.com/ExpansionPak/ModernGekko) | Runtime integration and game-port tooling |
| [DolRecomp: ExpansionPak and contributors](https://github.com/ExpansionPak/DolRecomp) | Ahead-of-time PowerPC code generation |
| [RecompCore: ExpansionPak and contributors](https://github.com/ExpansionPak/RecompCore) | Dolphin-derived static-recompilation runtime and GXRuntime |
| [Dolphin Emulator contributors](https://github.com/dolphin-emu/dolphin) | GameCube graphics, audio, input and hardware implementation, including Metal |
| [ModernGekko-Template](https://github.com/ExpansionPak/ModernGekko-Template) | Extraction, generation and module-build pipeline |
| [StrikersRecomp](https://github.com/aharonahdoot/StrikersRecomp) | Recompilation and packaging research reference |
| [Douglas Whittingham](https://github.com/ExpansionPak/RecompCore/pull/6) | ARM64 StaticRecomp fallback-contract repair |
| [joeblack2k](https://github.com/chrissotraidis/sunpad/pull/32) | Apple TV feasibility and later widescreen, audio, controller, Simulator and staging contributions |
| [gamemasterplc](https://github.com/chrissotraidis/RecompCore/blob/codex/sunpad-apple/Data/Sys/GameSettings/GMSE01.ini) | Sunshine widescreen and 60 FPS codes, kept with their original credit |

ModernGekko's [upstream credits](https://github.com/ExpansionPak/ModernGekko#credits)
also name SpecialK / aharonahdoot for RecompCore and Literally God / MrPoloGit
for the template and macOS support. The forks keep their upstream names and
history, and their contributor history, license texts and per-file notices
remain authoritative.

## AI assistance and artwork

SunPad development uses AI assistance. The maintainer is responsible for
understanding, reviewing and validating accepted changes. This doesn't imply
upstream participation or endorsement.

The app icon is AI-generated. Its provenance is in the
[iOS asset record](apple/ios/Assets.xcassets/AppIcon.appiconset/PROVENANCE.md).
The Apple TV artwork, retired with the legacy Apple TV app, is recorded at the
[legacy-engine-final](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/apple/tvos/Assets.xcassets/PROVENANCE.md)
tag. Gameplay screenshots show the original game, whose characters, artwork
and trademarks belong to their rights holders.
