# Credits and provenance

SunPad is an Apple application and Sunshine integration built on other projects.
Their tools and hardware implementations make it possible.

| Project | Contribution |
| --- | --- |
| [ModernGekko: Hyperway, ExpansionPak and contributors](https://github.com/ExpansionPak/ModernGekko) | Runtime integration and game-port tooling |
| [DolRecomp: ExpansionPak and contributors](https://github.com/ExpansionPak/DolRecomp) | Ahead-of-time PowerPC code generation |
| [RecompCore: ExpansionPak and contributors](https://github.com/ExpansionPak/RecompCore) | Dolphin-derived static-recompilation runtime and GXRuntime |
| [Dolphin Emulator contributors](https://github.com/dolphin-emu/dolphin) | GameCube/Wii graphics, audio, input and hardware implementation, including Metal |
| [ModernGekko-Template](https://github.com/ExpansionPak/ModernGekko-Template) | Extraction, generation and module-build pipeline |
| [doldecomp/sms](https://github.com/doldecomp/sms) | Sunshine research reference, not the executable runtime |
| [sms-english: GMSE01 decompilation](https://github.com/chasem-dev/sms-english) | CC0 GMSE01 symbol map and decompiled source used as a research reference; planned hash-checked build input for profiling and native replacements |
| [sms-pc-port: chasem-dev and contributors](https://github.com/chasem-dev/sms-pc-port) | Research reference for the [improvement plan](docs/IMPROVEMENT-PLAN.md). No code is used; the repository has no license |
| [StrikersRecomp](https://github.com/aharonahdoot/StrikersRecomp) | Recompilation and packaging research reference |
| [Douglas Whittingham](https://github.com/ExpansionPak/RecompCore/pull/6) | ARM64 StaticRecomp fallback-contract repair |
| [joeblack2k](https://github.com/chrissotraidis/sunpad/pull/32) | Apple TV feasibility and subsequent widescreen, audio, controller, Simulator and staging contributions |
| [gamemasterplc](https://github.com/chrissotraidis/RecompCore/blob/codex/sunpad-apple/Data/Sys/GameSettings/GMSE01.ini) | Sunshine widescreen and 60 FPS codes retained with their original credit |
| [GalaxyPad](https://github.com/chrissotraidis/galaxypad) | Dependency-verification approach and shared engineering-review findings |

ModernGekko's [upstream credits](https://github.com/ExpansionPak/ModernGekko#credits)
also identify SpecialK / aharonahdoot for RecompCore and Literally God /
MrPoloGit for the template and macOS support. Original contributor history,
license texts and per-file notices remain authoritative.

SunPad's work includes the Apple app, touch editor, settings, import/save handling,
controller integration, diagnostics, packaging and GMSE01-specific compatibility
work. It does not claim authorship of the recompiler or Dolphin hardware runtime.
The maintained forks retain upstream names and history. See the
[pinned source graph](docs/DEPENDENCIES.md) and [third-party notices](THIRD_PARTY_NOTICES.md).

## AI assistance and artwork

SunPad development has used AI assistance. The maintainer is responsible for
understanding, reviewing and validating accepted changes. This does not imply
upstream participation or endorsement.

The app icon is AI-generated. Its retained provenance is in the
[iOS asset record](apple/ios/Assets.xcassets/AppIcon.appiconset/PROVENANCE.md).
The [tvOS asset record](apple/tvos/Assets.xcassets/PROVENANCE.md) describes the
Apple TV artwork. Gameplay screenshots document the original game, whose
characters, artwork and trademarks remain the property of their rights holders.
