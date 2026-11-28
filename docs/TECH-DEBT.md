# Technical debt

Last updated: 28 November 2026, for SunPad 0.4.0. The legacy engine's
performance and stability record (AOT module, Dolphin's renderer, EFB
readbacks, 60 FPS experiments) is in
[TECH-DEBT.md at legacy-engine-final](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/TECH-DEBT.md).

## Performance

| Item | Evidence | Next step |
| --- | --- | --- |
| Area loads upload many textures in one frame | 232.8 ms for 130 uploads, iPhone 14 play, 26 November 2026 | Spread uploads over frames in the fork's renderer |
| MoltenVK 1.4.2 has no `VK_EXT_graphics_pipeline_library`, so each new pipeline is compiled whole | 80 to 150 ms per pipeline on the A15. `SMS_VK_ASYNC_PIPELINES` moves them off the game's frame, at the cost of draws appearing late | Revisit when MoltenVK adds pipeline libraries, or warm common pipelines at boot |
| The engine is built at `-O2` (RelWithDebInfo) | A Release `-O3` build lost a game symbol at link (23 November 2026) | Find the symbol, then measure `-O3` |
| 60 FPS unmeasured on devices | Only 30 FPS routes have run | Plaza and Bianco routes with `SMS_FRAME_RATE=60` on both devices |

## Structure

| Item | Why it is there | Next step |
| --- | --- | --- |
| `SunPadCoreHost.h` keeps 0.3.x names (`gameRoot`, `modulePath`, `currentVPS`, `currentPerformanceProfile`) | The view controller and overlay kept their wiring when the legacy engine went | Rename to the engine's terms in one commit with its callers |
| The engine is configured through `SMS_*` environment variables set before it loads | Some engine parts read them in the library's initializers | A settings field in `sms_embed.h` if upstream takes the interface |
| The engine runs once per process | The game has no shutdown path, as on the console | None planned. Reimport asks for a restart |
| Ten fork commits on `sunpad` | The embedded build, device memory base, retail UI and async pipelines | Offer them upstream when the maintainer decides |
| The Mac development app is still named SunPad Next | It is outside 0.4.0 | Rename with the Mac app's release |
| No Apple TV target | Removed with the legacy engine | Build one around the engine host |
| PadMint's `disk_gb` is an estimate (8) | Not measured from a clean build yet | Measure a clean PadMint build and set it |

## Verification gaps

| Gap | Next step |
| --- | --- |
| CI has no device or Simulator gameplay | Keep running `run-engine-route.sh` on a device before releases |
| External displays, wired controllers and reconnecting after sleep | A device session ([KNOWN_ISSUES.md](KNOWN_ISSUES.md#not-checked-yet)) |
| Long sessions for heat and battery | An hour on the iPhone 14 with the engine log |
