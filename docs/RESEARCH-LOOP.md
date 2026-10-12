# Comparative research loop

- **Started:** 2026-10-11
- **Feeds:** [improvement plan](IMPROVEMENT-PLAN.md) through its
  [candidate intake](IMPROVEMENT-PLAN.md#adding-new-work)
- **Run log:** [IMPROVEMENT-LOG.md](IMPROVEMENT-LOG.md)

Players compare SunPad with other Super Mario Sunshine projects. This loop
turns those comparisons into SunPad work: read what another project does, write
down the behavior in our own words, check what SunPad already has, and promote
the useful gaps into the improvement plan. SunPad's own code then implements
them inside its architecture (the retail program translated ahead of time on
the Dolphin-derived runtime, with the Apple app on top).

Use this loop when asked to compare SunPad with another Sunshine project, to
look for features or fixes to learn from, or to refresh the inventory below.

## Source rules

| Source | License | Read | Reuse in SunPad |
| --- | --- | --- | --- |
| [sms-pc-port](https://github.com/chasem-dev/sms-pc-port) | None (all rights reserved) | README, docs, commit messages, issues; source only to locate a game behavior | Nothing. No code, patches, data tables or assets |
| [SMS Launcher](https://github.com/chasem-dev/sms-launcher) | MIT | Everything | Code only with its MIT notice in [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md). It is an Electron app, so treat it as a behavior reference |
| [sms-english](https://github.com/chasem-dev/sms-english) and [doldecomp/sms](https://github.com/doldecomp/sms) | CC0 | Everything | Yes, with the revision cited |
| [Dolphin](https://github.com/dolphin-emu/dolphin) | GPL-2.0-or-later | Everything | Yes, through the maintained runtime forks |
| Community texture packs, cutscene packs, artwork | Their authors' terms | Format and behavior | Never bundled or downloaded by SunPad |

**How a finding becomes SunPad code:**

1. **Write a behavior note** before implementing. Describe what the player
   sees and what the game does, in your own words, with a link and revision for
   where you learned it. Do not paste code or patch hunks. Names that belong to
   the game itself (decompilation symbols, addresses) are facts and may be used.
2. **Confirm game facts in the CC0 decompilation**, Dolphin or a SunPad
   measurement. A claim that exists only in the unlicensed port's source is not
   ready to use.
3. **Implement from the note**, the decompilation, Dolphin and SunPad's own
   code. Keep the unlicensed source closed while writing SunPad code.
4. **Cite the note** in the pull request and the log entry.

## The loop

One pass reads for at most two hours and lands one documentation pull request.
Run a pass when asked, once per plan phase, or when players report a new
comparison.

1. **Record revisions.** Note the current commit of each project you read and
   compare with the last row of the [pass table](#passes). If nothing changed,
   log `no change` and stop.
2. **Read what changed** since the last pass: commit subjects, changed docs,
   README, issues (open and recently closed) and SMS Launcher's
   `changelog.json`.
3. **Update the [inventory](#inventory)**: one row per capability a player
   would notice. The SunPad column must name the file, setting or document that
   shows SunPad's current state. Do not rely on memory.
4. **Classify each row:**
   - **Have:** SunPad already does this.
   - **Plan:** an existing task card covers it. Add the new finding to that card.
   - **Promote:** a gap SunPad can close without new performance headroom.
   - **Measure:** worth doing only if a SunPad measurement shows the cost or
     defect. Add it to the log's ideas list.
   - **Not now:** does not fit SunPad's platforms, headroom or data rules. Say why.
5. **Promote at most three rows** into the plan as task cards, using the
   player-feature rule in [candidate intake](IMPROVEMENT-PLAN.md#adding-new-work).
6. **Record.** Add a row to the pass table, append a `research pass` log entry,
   and open the documentation pull request. Implementation happens later
   through the plan's goal loop.

## Passes

| Pass | Date | SMS Launcher | sms-pc-port | Decompilation pin | Result |
| --- | --- | --- | --- | --- | --- |
| 1 | 2026-10-11 | `b460678` (v0.1.57) | `a8669e0` | `967436b` | 3 promoted (10.1-10.3); 7.1 and 8.1 updated; 5 ideas |

## Inventory

Updated in pass 1. SMS Launcher sets up and runs sms-pc-port on Windows, Linux
and Mac. sms-pc-port compiles the decompilation as a native desktop program
with an OpenGL renderer. Its Mac build is x86_64 and runs under Rosetta 2 on
Apple silicon; native arm64 and iOS are not supported
([review](SMS-PC-PORT-REVIEW.md#why-it-cannot-be-dropped-into-sunpad)).
Their features are listed for comparison; their platforms set different limits.

### Saves

| Capability | SMS Launcher / sms-pc-port | SunPad today | Class | Next |
| --- | --- | --- | --- | --- |
| Import a Dolphin `.gci` save, export saves | Import with header checks and a backup first | None. Saves live in `Library/Application Support/SunPad/GC/USA/Card A` (`sunPadSupportRoot` in `SunPadGameViewController.mm`), which Files cannot see | Promote | [Task 10.1](IMPROVEMENT-PLAN.md#pass-10-player-features) |
| Dated backups around play, restore | Before and after each session, before updates | No backups | Plan | Task 1.3; task 10.1 backs up before an import |

### Input

| Capability | SMS Launcher / sms-pc-port | SunPad today | Class | Next |
| --- | --- | --- | --- | --- |
| Controller rumble | Added 2026-10-10 | Apple TV only (`SunPadTVSetRumble` in `SunPadTVAppDelegate.mm`); none on iPhone or iPad | Promote | Task 10.2 |
| Invert camera left/right and up/down | Both, both on by default | Left/right only ("Modern C-stick L/R", `SunPadInputPipeEncoder`) | Promote | Task 10.3 |
| Button remapping | Keyboard and controller | Controller Button Mapping, touch layout editor | Have | |
| Free camera, camera speed | Game-code changes | None | Not now | Changes game code; revisit with the mod work in pass 3 |
| Button prompts that match the controller | Replaced button textures | None | Measure | Needs task 7.1 and original artwork |

### Display

| Capability | SMS Launcher / sms-pc-port | SunPad today | Class | Next |
| --- | --- | --- | --- | --- |
| Widescreen with the HUD kept 4:3 or at the edges | Yes | 16:9 with Sunshine's widescreen code; open defects ([#23](https://github.com/chrissotraidis/sunpad/issues/23)) | Plan | Task 9.1 |
| Heat-wave effect on/off | Separate setting | Turned off only with widescreen; the patch sends a 16 KiB chunk to the interpreter ([known issues](KNOWN_ISSUES.md)) | Measure | Ideas: a bypass that does not change code bytes |
| Internal resolution | Yes | Render Resolution menu | Have | |
| MSAA, FXAA, anisotropic filtering, sharpening, FSR, HDR, presets | Yes | None | Not now | Needs GPU headroom iPhones lack; revisit for Macs and M-series iPads after goal 2 |
| HD texture packs | Dolphin-format packs with load policies | None | Plan | Task 7.1, with pass 1 loading findings |
| HD cutscenes | Third-party video packs | None | Not now | Large third-party downloads; SunPad does not fetch content |

### Performance and feel

| Capability | SMS Launcher / sms-pc-port | SunPad today | Class | Next |
| --- | --- | --- | --- | --- |
| 60 and 120 FPS | 60 by default; 42 frame-rate patches and two timing write-ups | Original 30 FPS; unstable 60 FPS Gecko patch | Plan | Tasks 8.1-8.2, with pass 1 audit entries |
| No stutter in a stage's first moments | Compiles each stage's recorded shader programs while it loads | Hybrid ubershaders on iOS; targeted warmup suggested in [technical debt](TECH-DEBT.md) | Measure | Ideas: per-stage pipeline warmup |
| Clean audio after slow frames | Fixed replayed and dropped audio blocks; grows the queue after an underrun | Dolphin audio path; see [audio issue](AUDIO_ISSUE.md) | Measure | Ideas: check for replayed blocks and underruns |
| Frame-time overlay | Per-subsystem breakdown | FPS counter; diagnostic report | Plan | Task 2.3 |
| Skip cutscenes | Yes | None | Not now | Changes game code; low player value against the cost |

### Setup, support and content

| Capability | SMS Launcher / sms-pc-port | SunPad today | Class | Next |
| --- | --- | --- | --- | --- |
| Guided setup | Disc choice, downloads, build | Files import; PadMint builds | Have | |
| Logs for support | Activity log, copy and save | Report a Problem… shares a diagnostic report with the app version | Have | |
| In-app changelog, automatic updates, Beta channel | Yes | None; releases are paused ([AGENTS.md](../AGENTS.md)) | Not now | Revisit when releases resume |
| Steam, Steam Deck, Discord presence | Yes | Not applicable on Apple devices | Not now | |
| Cheat menu | Dear ImGui menu | None | Not now | Low priority; Gecko codes slow chunks down |
| Super Mario Eclipse | Patches the user's disc into the mod | None | Not now | A different program: it would need its own module, and code it loads at run time would use the interpreter |
