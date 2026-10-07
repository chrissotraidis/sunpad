# SunPad Android feasibility

- **Assessment date:** 2026-08-11
- **SunPad source assessed:** `e130332cf13cc35456f8116a35056ce98ccf8d7a`
- **ModernGekko source assessed:** `048c426ba3db0369e40826d22ad3adcce7fe7c58`
- **Vendored RecompCore/Dolphin source assessed:** `e13ab348f13cd67879f6db6e9d7185410f8f62c6`
- **DolRecomp source assessed:** `93b881c8f73df1d64a88491f2aa50c7c9ed2384d`
- **Assessment type:** source, architecture, and toolchain review; no Android APK was built or run

October 2026 note: the module and runtime passes in the
[improvement plan](IMPROVEMENT-PLAN.md) (safe direct calls, exact native math,
specialized vertex loaders and atomic saves) live in the shared DolRecomp and
RecompCore code, so an Android port would inherit them. The GPU readback pass
targets the Metal backend and would need an equivalent for OpenGL ES or Vulkan.

## Executive verdict

SunPad can be brought to Android from the existing macOS development stack.
The GameCube extraction and DolRecomp generation steps remain Mac-hosted, while
the Android NDK cross-compiles the generated C module and ModernGekko runtime
for `arm64-v8a`. Gradle then packages those native products into an APK. There
is no need to compile PowerPC code on the phone, stream gameplay, or rewrite
Super Mario Sunshine.

This is not a build-target toggle. SunPad currently has an Apple-only product
shell and ModernGekko currently has no Android host branch of its own. Android
needs a thin app and JNI layer, an Android `ANativeWindow` platform for the
ModernGekko runtime, Android storage/import code, and a recreation of the touch
and settings experience. The pinned Dolphin-derived core already contains
working Android EGL/OpenGL ES, Vulkan, OpenSL ES, controller, surface, JNI, and
Gradle reference implementations, which makes the project technically credible
rather than speculative.

Estimated cumulative effort for one experienced Android NDK/C++ engineer
working full time:

| Outcome | Estimated effort | What it proves |
|---|---:|---|
| Android module-only cross-build | 2-5 days | The current generated GMSE01 C sources produce a loadable Android ARM64 ELF module |
| Controller-driven technical proof | 2-4 weeks | A debug APK installs, loads the AOT module, renders coherent gameplay, produces audio, and accepts a controller on one physical phone |
| Usable Android alpha | 6-10 weeks | In-app disc import, private extraction, saves, lifecycle, controller play, and a fixed complete touch layout work on representative hardware |
| Apple-experience parity | 12-20 weeks | The settings, editable controls, controller mapping, diagnostics, accessibility, update preservation, and phone/tablet behavior match SunPad's supported Apple experience |
| Public release quality | 16-26 weeks | Reproducible packaging, multi-device validation, 16 KB page support, legal/source delivery, documentation, and release safeguards are complete |

These ranges are planning estimates, not delivery promises or Android runtime
evidence. Someone learning the Android NDK, JNI, Gradle, or Dolphin's Android
surface lifecycle during the port should allow roughly five to eight calendar
months for release quality.

## What can be shared with the Apple build

The cleanest architecture is one game/runtime stack with separate platform
shells:

```text
User-owned supported GMSE01 image on the Mac
                    |
                    v
        DolRecomp extract + generate C
                    |
          +---------+----------+
          |                    |
          v                    v
 AppleClang arm64        Android NDK arm64-v8a
 gGMSE01_recomp.dylib    libgGMSE01_recomp.so
          |                    |
          v                    v
 ModernGekko + Metal     ModernGekko + EGL/GLES
 Apple app shell         Kotlin/JNI Android shell
```

The generated module is host-neutral C plus a small C runtime and module ABI.
The existing `module-template/CMakeLists.txt` already creates `.dylib`, `.so`,
or `.dll` products according to the target toolchain. SunPad's current GMSE01
generation contains 221 C chunks and occupies about 220 MiB before compilation;
the current optimized iOS module is about 81 MiB. Android should expect a
similarly substantial native library and must measure APK size, install size,
link time, and cold-load time early.

The game image remains user-owned and device-local. The Android APK can contain
the ahead-of-time recompiled executable module, as the current preview IPA does,
but it must not contain the disc image, extracted filesystem, saves, settings,
logs, signing material, or personal build paths.

## Evidence in the current source

### The module build is already cross-platform in shape

`scripts/ios-build-core-device.sh` builds the game module separately from the
app by configuring `vendor/dolphin/module-template` with a platform toolchain,
`GAME_ID=GMSE01`, the generated source directory, GXRuntime, and the StaticRecomp
ABI directory. An Android module script can use the same inputs with the NDK's
official CMake toolchain and `ANDROID_ABI=arm64-v8a`.

The module exports only `staticrecomp_get_module`, validates its ABI and game ID
before runtime use, and links no game assets. The existing Linux/ELF version
script is also applicable to Android. One packaging adjustment is required:
the module target currently suppresses the normal `lib` prefix, while Android
recognizes packaged native libraries in the conventional
`lib/<abi>/lib<name>.so` form. Android should produce or stage
`libgGMSE01_recomp.so`, package it as a normal app native dependency, and attach
its descriptor through ModernGekko's existing in-process module API.

### The production CPU core is already selected independently of Apple

`src/runtime/dolphin_runtime.cpp` explicitly selects Dolphin's
`PowerPC::CPUCore::StaticRecomp` and supplies the validated module. That choice
is outside the iOS preprocessor branch, so the Android runtime can use the same
AOT execution core.

On ARM64 platforms other than iOS, the current StaticRecomp implementation may
create a `JitArm64` fallback for missing or invalidated regions. SunPad's Apple
contract instead uses the module plus interpreter fallback. The first Android
product build should make this an explicit, testable configuration and default
to **no PowerPC fallback JIT**, preserving the same execution claim and making
native-dispatch evidence comparable between platforms. A diagnostic fallback
JIT build may be useful to isolate performance problems, but it must be labeled
separately and must never conceal a module that failed to load.

Android can still use Dolphin's ARM64 vertex loader. That graphics-side code
generation does not translate the game's PowerPC CPU instructions and is
separate from the PowerPC execution policy.

### The pinned Dolphin core already supports Android

The vendored source has a complete `Source/Android/` Gradle/JNI application and
Android-specific core paths. In particular it provides:

- a native `main` shared-library target and JNI bridge;
- `ANativeWindow_fromSurface`, `WindowSystemType::Android`, and live presenter
  surface replacement;
- EGL and OpenGL ES support, plus Vulkan as a second backend;
- an OpenSL ES sound backend;
- Android controller and input-device handling;
- app-private user-directory setup and Java/Kotlin lifecycle reference code;
- `arm64-v8a` and `x86_64` ABI filters; and
- a current native-build baseline of AGP 9.1.0, Gradle 9.4.1, compile/target SDK
  36, NDK `29.0.14206865`, Java 17 language level, and minimum SDK 24.

This code is reference and reusable runtime infrastructure, not a drop-in
SunPad application. Shipping Dolphin's complete general-purpose game browser
would be the wrong product boundary. SunPad should expose only its supported
GMSE01 flow and should carry the smallest Android-specific patch set needed by
ModernGekko.

### The current ModernGekko frontend needs an Android seam

ModernGekko's top-level CMake has explicit iOS, macOS, Windows, X11, and Wayland
platform creation, but no `PlatformAndroid` creation path. When CMake targets
Android, the vendored Dolphin project also unconditionally adds its full Android
JNI `main` target. A clean SunPad port therefore needs two bounded build changes:

1. allow ModernGekko to consume the Android-capable Dolphin core without
   automatically building the full Dolphin Android frontend; and
2. add a thin ModernGekko Android platform/JNI target that creates the runtime
   with an Android surface and handles surface replacement.

These changes belong in reviewed Android patch snapshots parallel to the
existing Apple snapshots. They should not be hand-edited only under ignored
`ref/` directories.

### The Apple product layer is substantial but has narrow native seams

The Apple shell contains roughly 3,350 lines across its overlay, view
controller, core host, mixer, and controller mapping. UIKit and Objective-C++
cannot be compiled directly into the Android app. The behaviors can still be
recreated without touching Sunshine gameplay code because they converge on a
small normalized `SunPadInputState` and Dolphin pipe-command protocol.

The portable parts of `SunPadInputState`, strongest-input mixer, rising-edge
latching, controller mapping rules, and pipe encoder should be moved into
platform-neutral C/C++ files with the existing tests kept intact. UIKit and
GameController storage wrappers can remain Apple-specific; Kotlin can own the
Android views, `SharedPreferences` or DataStore, and Android controller events.

## Recommended Android architecture

```text
SunPadActivity (Kotlin)
  +-- SurfaceView
  |     +-- SurfaceHolder.Callback
  |           +-- JNI surfaceCreated/surfaceChanged/surfaceDestroyed
  +-- SunPadOverlayView
  |     +-- touch controls, menu, loading/error state, accessibility
  +-- Android controller events
  +-- Storage Access Framework picker
  +-- private preferences and diagnostic sharing
        |
        v
libsunpad.so (C++/JNI)
  +-- portable SunPad input mixer + pipe encoder
  +-- portable disc validation/extraction service using Dolphin DiscIO
  +-- ModernGekko Runtime on a dedicated native thread
  |     +-- PlatformAndroid + ANativeWindow
  |     +-- StaticRecomp CPU core
  |     +-- EGL/OpenGL ES backend
  |     +-- OpenSL ES initially
  +-- packaged libgGMSE01_recomp.so
```

Use a conventional `SurfaceView` first. Dolphin's pinned Android code already
demonstrates the required `ANativeWindow` and presenter lifecycle. GameActivity
is a viable future shell, but introducing it during the first proof adds another
abstraction without removing any known blocker.

## Proposed repository layout

```text
android/
  settings.gradle.kts
  build.gradle.kts
  gradle/wrapper/
  app/
    build.gradle.kts
    src/main/AndroidManifest.xml
    src/main/java/.../SunPadActivity.kt
    src/main/java/.../SunPadOverlayView.kt
    src/main/cpp/CMakeLists.txt
    src/main/cpp/SunPadAndroidHost.cpp
    src/main/cpp/SunPadAndroidPlatform.cpp
  Provisioned/
    jniLibs/arm64-v8a/libgGMSE01_recomp.so   # ignored, generated locally
scripts/
  android-build-module.sh
  android-build-app.sh
  audit-android-package.sh
patches/
  ModernGekko/                               # Android delta added to snapshot
  ModernGekko-dolphin/                       # Android/runtime delta if required
```

The provisioned native module must be ignored just like
`apple/ios/Provisioned/`. Gradle should read it as a `jniLibs` source directory.
The preferred host integration is to import and link that packaged library into
`libsunpad.so`, call its exported descriptor function, and supply
`ModuleSource::AttachedDescriptor` to the runtime. This uses Android's normal
native-library loader and avoids copying or loading executable code from a
writable game-data directory. A name-based `dlopen` of the packaged library is
a fallback design, not the first choice.

## Build plan from macOS

### 1. Pin the host toolchain

The first implementation should reproduce the versions already exercised by
the pinned Dolphin Android project rather than inventing a second matrix:

| Component | Initial pin |
|---|---|
| JDK | 17-compatible toolchain |
| Android Gradle Plugin | 9.1.0 |
| Gradle wrapper | 9.4.1 |
| compile/target SDK | 36 |
| minimum SDK | 24, raise only if a measured dependency requires it |
| NDK | `29.0.14206865` |
| CMake | 3.22.1 or newer version accepted by the pinned project |
| First product ABI | `arm64-v8a` only |

The assessment host currently has SDK platforms 34 through 36 but no installed
NDK, so this assessment did not attempt a module or APK build. Toolchain setup
is the first reproducibility task, not Android runtime proof.

### 2. Cross-compile the module first

The first new script should stop after producing and inspecting the module. Its
essential configuration is:

```sh
cmake -S ref/ModernGekko/vendor/dolphin/module-template \
  -B build/android-module-arm64 -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=Release \
  -DGAME_ID=GMSE01 \
  -DGENERATED_DIR="$SUNPAD_GENERATED_DIR" \
  -DGXRUNTIME_DIR="$SUNPAD_GXRUNTIME_DIR" \
  -DCHASSIS_ABI_DIR="$SUNPAD_STATICRECOMP_ABI_DIR"
cmake --build build/android-module-arm64 --parallel
```

The checked-in script should derive those directories from the repository,
accept an explicit NDK location, use a build directory outside tracked source,
and stage only the final ELF library under `android/Provisioned/`. It should
verify:

- ELF64 AArch64 identity;
- Android API/minimum-version metadata where available;
- the single `staticrecomp_get_module` export;
- no unresolved non-platform dependencies;
- 16 KB ELF segment alignment;
- no retail-data strings, personal paths, or credentials; and
- deterministic hash behavior across two unchanged builds, or a documented
  reason for any build-ID difference.

This gate isolates the most important question: whether the current generated
Sunshine module is accepted by Android Clang and Bionic before JNI, rendering,
or UI work obscures failures.

### 3. Add the thin native host target

The ModernGekko Android CMake path should:

- retain `ANDROID=1` so Dolphin builds its Android core, EGL, input, and audio
  support;
- disable the complete upstream Dolphin Android `main` frontend target;
- build `moderngekko`, `core`, `uicommon`, `discio`, `inputcommon`, the chosen
  video backend, and one SunPad JNI shared library;
- import the packaged GMSE01 library, link it as a native dependency, and attach
  its descriptor through ModernGekko's existing attached-module API;
- add `PlatformAndroid` creation to the runtime;
- set `_ARCH_64` and `_M_ARM_64` through the existing architecture logic;
- select `StaticRecomp` and require a valid GMSE01 module;
- expose an explicit `allow_fallback_jit` or equivalent product setting, with
  the release default off;
- enable Android's native ARM64 vertex loader unless physical evidence requires
  the software path; and
- preserve source-prefix mapping so packaged binaries do not leak host paths.

The JNI surface should be intentionally small: initialize paths, create/start,
pause/resume, stop/join, publish input, surface replacement, import/extraction
progress, and diagnostics. Do not mirror the entire Dolphin JNI API.

### 4. Bring up rendering with OpenGL ES

Start with Dolphin's existing EGL/OpenGL ES backend and an Android
`WindowSystemInfo` whose render surface is an `ANativeWindow*`. This is the
shortest path from the current core to pixels. Record the renderer, EGL/GL
version, vendor, device, extensions, internal resolution, frame cadence, and
surface dimensions at launch.

The first proof must handle:

- no runtime start until a valid surface exists;
- `surfaceDestroyed` pausing the core before releasing the window;
- `surfaceChanged` replacing the presenter's surface without creating a second
  runtime;
- app resume only after a valid replacement surface exists;
- display cutouts, navigation modes, and landscape resizing; and
- failure with a readable error when required GLES features are unavailable.

Vulkan is a later fallback or optimization path, not a prerequisite. It should
be evaluated only after the OpenGL ES proof establishes whether the bottleneck
is API capability, driver behavior, or the wider runtime.

### 5. Use the existing Android audio backend for proof

The pinned Dolphin core already builds an OpenSL ES backend on Android and
selects it as the Android default. Use that path for Phase A because it tests
the game/runtime with the fewest new variables. Android now recommends Oboe or
AAudio for new high-performance audio work, so release planning should include
a measured decision:

- retain OpenSL ES if representative devices show stable latency, routing, and
  underrun behavior; or
- add Oboe/AAudio behind the same Dolphin sound-stream boundary if evidence
  shows the current backend is inadequate.

Do not migrate audio APIs before proving whether the existing backend works.
SunPad's iOS DSP/timing history makes actual music, voice, effects, and long-run
underrun evidence mandatory; a successful callback or audible menu click is not
an audio acceptance pass.

### 6. Prove controller gameplay before touch UI

The first Android APK should use one physical controller so touch layout work
does not block core validation. Kotlin should receive Android `KeyEvent` and
`MotionEvent` input, distinguish `SOURCE_GAMEPAD`, `SOURCE_DPAD`, and
`SOURCE_JOYSTICK`, normalize dead zones and triggers, and publish the same
`SunPadInputState` consumed by Apple.

Reuse the pipe protocol initially. It already maps one normalized snapshot to
Dolphin's GameCube controller device and has focused regression tests. Preserve
the current strongest-axis merge, maximum-trigger merge, rising-edge latching,
button remapping, and horizontal-only modern C-stick option. Test controllers
that expose the D-pad both as key codes and as hat axes.

### 7. Port import and private storage transactionally

Use `ACTION_OPEN_DOCUMENT` to let the user select one ISO/GCM through Android's
Storage Access Framework. The result is a content URI, not a durable ordinary
filesystem path. The app should stream it once into private internal storage
and never request broad external-storage permissions.

The Android import must preserve SunPad's current contract:

1. Create `GameData.import-<uuid>` under the same private volume as active data.
2. Stream the selected URI to `GMSE01.iso` while checking size, header, game ID,
   disc number/revision, and SHA-256.
3. Extract with Dolphin `DiscIO` into the staged `GMSE01/` directory.
4. Require the current critical system/game files and exactly 174 regular files
   under `files/`.
5. Flush staged files and metadata before activation.
6. Stop the runtime, atomically swap the complete staging directory into
   `GameData`, and restore the previous directory if activation fails.
7. On next launch, detect and remove or recover interrupted staging/backup
   directories before boot.
8. Derive active paths from the current app sandbox every launch; never persist
   a container-root absolute path as identity.

Store the disc, extracted root, Dolphin user directory, saves, settings, and
logs in app-private internal storage. An in-place APK update must preserve all
of them. Uninstall normally removes app-private data, so a future explicit save
export/import feature is separate product work and must never expose the disc
image by accident.

### 8. Recreate the mobile product layer in Kotlin

After controller gameplay passes, place a Kotlin custom view above the
`SurfaceView` and feed its state into the same mixer. Reproduce behavior rather
than translating UIKit classes line by line:

- complete simultaneous multi-touch with stable pointer ownership;
- main stick, C-stick, D-pad, A/B/X/Y/Z, Start, L/R buttons, and analog trigger
  pressure where the UI exposes it;
- pass-through touches outside controls;
- loading, error, import, remove-data, and diagnostic states;
- render scale, aspect ratio, FPS, experimental 60 FPS, opacity, global size,
  per-control size, layout editing/reset, controller hiding, button mapping,
  and modern C-stick settings;
- normalized safe-content coordinates instead of raw screen pixels;
- separate phone/tablet and handedness profiles if parity requires them;
- TalkBack labels, values, actions, focus order, and state announcements; and
- cancellation of every held or latched input on pause, focus loss, controller
  removal, and surface loss.

Use ordinary Android preference storage for product settings and keep runtime
files in private storage. The Apple and Android preference implementations need
matching semantics, not matching platform APIs or serialized formats.

### 9. Package, audit, and automate

`android-build-app.sh` should bootstrap exact dependencies, require the locally
provisioned GMSE01 module, invoke the pinned Gradle wrapper, and emit a retail-
free debug or release APK. `audit-android-package.sh` should verify at least:

- ZIP integrity and safe paths;
- expected package ID, version, minimum/target SDK, and landscape policy;
- exactly the supported native ABI for the first release;
- presence and ELF identity of the SunPad host and GMSE01 module;
- module export and host/module ABI agreement;
- 16 KB ZIP and ELF alignment for every native library;
- absence of ISO/GCM/RVZ/WIA/WBFS/GCZ files, extracted assets, saves, logs,
  keystores, certificates, credentials, and personal absolute paths;
- required GPL license, notices, corresponding-source link, and install guide;
- APK signature state and signer identity for signed artifacts; and
- SHA-256 output for direct APK distribution.

Source-only CI can build the Android host and a non-retail fixture module for
ABI/loading tests. A playable release module still comes from the reviewed
local generation path and is supplied to the packaging job without committing
generated C, retail data, or signing secrets.

The native build must support 16 KB page-size devices from the first proof.
Use the pinned modern NDK/AGP path, retain Dolphin's flexible-page-size option,
inspect every packaged `.so`, and run at least one 16 KB emulator install/launch
gate. An ordinary 4 KB phone pass does not prove this requirement.

## Reusable work versus Android-specific work

| Existing area | Expected reuse | Android work |
|---|---|---|
| DolRecomp GMSE01 generation | Very high | Invoke the NDK instead of AppleClang for the final module |
| Generated module and ABI | Very high | Android library naming, ELF inspection, packaging, and load path |
| StaticRecomp CPU/timing fixes | High | Prove ARM64/Bionic behavior and explicitly control fallback JIT |
| Dolphin hardware services | High | Build the Android-supported core configuration |
| Renderer | High | Use Dolphin EGL/GLES first; surface lifecycle and driver validation are new |
| Audio/DSP runtime | High | Use OpenSL ES initially; Android routing/latency acceptance is new |
| Disc validation/extraction rules | High | Port the wrapper to portable C++/JNI and read from a content URI staging file |
| Saves and Dolphin user directory | High | Place under app-private internal storage and prove update survival |
| Normalized input and pipe protocol | High | Extract portable C++ logic; add Android event and touch producers |
| Controller mapping behavior | Medium to high | Kotlin persistence/UI and Android device quirks |
| Touch overlay and menus | Behavioral specification only | Recreate in Kotlin with Android layout, insets, multi-touch, and TalkBack |
| Diagnostics and privacy contract | Conceptual reuse | Android rotating log, redaction, share intent, and crash guidance |
| Package/release audits | Conceptual reuse | APK/AAB, ELF, alignment, signing, and Android metadata checks |

## Phased implementation and go/no-go gates

### Phase 0: module and toolchain proof

**Expected duration:** 2-5 working days.

1. Install and pin JDK, SDK 36, NDK `29.0.14206865`, CMake, Ninja, and the
   Gradle wrapper without changing the Apple toolchain.
2. Add `android-build-module.sh` and the Android-only module prefix rule.
3. Compile the existing generated GMSE01 C module for `arm64-v8a` twice.
4. Verify ELF architecture, exports, dependencies, 16 KB alignment, size, and
   hashes.
5. Add a tiny host-side descriptor inspection test if the Android ELF can be
   loaded under an Android test process.

**Gate:** proceed only if Android Clang compiles and links the complete module
without source changes that would diverge from the Apple module ABI.

### Phase A: controller-driven physical-device proof

**Expected cumulative duration:** 2-4 weeks.

1. Add the minimal Gradle application and native SunPad JNI target.
2. Add the ModernGekko Android build/platform seam and reviewed patch snapshot.
3. Package the module under `lib/arm64-v8a/`, link the host to it, and validate
   its attached descriptor before boot.
4. Use developer tooling to place already validated game data in private
   storage; do not build the picker or touch overlay yet.
5. Bring up EGL/OpenGL ES, OpenSL ES, and one controller.
6. Prove intro, title, file select, Delfino Plaza, FLUDD pressure, pause/menu,
   one Shine objective, save creation, cold relaunch, and background/resume.
7. Capture StaticRecomp native/fallback counters and prove the module remained
   active rather than silently running a fallback core.

**Gate:** a physical ARM64 phone completes a coherent controller-driven
gameplay objective with stable rendering, audio, save, and lifecycle behavior.
A build, install, live process, title screen, or emulator-only run is not enough.

### Phase B: usable Android alpha

**Expected cumulative duration:** 6-10 weeks.

1. Add Storage Access Framework import, private staging, extraction, rollback,
   and interrupted-import recovery.
2. Add a fixed but complete touch layout with genuine multi-touch.
3. Add essential settings, loading/error UX, log sharing, and data removal.
4. Prove touch-only completion of the same Phase A gameplay objective.
5. Prove invalid/cancelled reimport preserves the working image and successful
   replacement preserves unrelated saves and settings.
6. Prove an in-place APK update preserves the image, extraction, save,
   preferences, controller mapping, and touch layout.

**Gate:** a new user can install the APK, select their own supported image,
play and save using touch without `adb`, relaunch, and continue.

### Phase C: Apple-experience parity

**Expected cumulative duration:** 12-20 weeks.

1. Complete editable controls, individual sizing, profile behavior, remapping,
   controller coexistence, aspect/render/FPS options, and experimental settings.
2. Complete TalkBack semantics and large-screen/tablet behavior.
3. Validate Android activity recreation, surface recreation, interruptions,
   controller hot-plug, audio routes, and input cleanup.
4. Exercise both Adreno- and Mali-class physical GPUs and at least one tablet
   or large-screen device.
5. Profile sustained gameplay, memory growth, shader stutter, battery/thermal
   behavior, audio underruns, and cold module load.

**Gate:** every supported Apple behavior has direct Android evidence or is
clearly documented as intentionally unsupported.

### Phase D: public release

**Expected cumulative duration:** 16-26 weeks.

1. Add clean-room host/module builds and source-only CI gates.
2. Complete APK audits, signing procedure, checksums, corresponding source,
   notices, installation/update guidance, and support boundaries.
3. Validate 4 KB and 16 KB page-size environments.
4. Repeat the complete physical acceptance matrix with the exact release APK.
5. Publish a sideloaded preview first. Treat Play Store policy, listing,
   developer verification, and AAB delivery as a later independent milestone.

**Gate:** the downloadable artifact itself, not a development build, passes the
package, install, import, gameplay, persistence, lifecycle, and privacy gates.

## Acceptance matrix

Compilation, packaging, installation, launch, runtime activity, and gameplay
acceptance are separate claims.

| Gate | Minimum evidence |
|---|---|
| Module build | Complete generated GMSE01 sources compile as 16 KB-compatible AArch64 ELF with the expected export |
| Host build | Clean pinned Gradle/NDK build of the SunPad JNI host from an asserted commit |
| Package | APK inventory, ABI, SDK levels, native alignment, notices, retail-data exclusion, signature, and checksum |
| Install | Fresh install and in-place update succeed on named physical devices |
| Launch | App starts, obtains a surface, validates the module, and keeps one runtime alive |
| AOT execution | StaticRecomp module stays active; native/fallback counters and fallback-JIT policy are recorded |
| Rendering | Coherent title, menus, gameplay, water, effects, text, and cutscenes on Adreno and Mali GPUs |
| Import | Supported image accepted; wrong/cancelled/interrupted replacement leaves old data usable |
| Touch | Complete touch-only objective with simultaneous stick, trigger, and face-button use |
| Controller | Cold-connect, hot-plug, axes, triggers, D-pad variants, remapping, pause, and disconnect cleanup |
| Audio | Music, voices, effects, FLUDD, route changes, interruptions, and underrun evidence over sustained play |
| Save | Create/load a save; bytes remain valid after cold relaunch, update, import, and background/resume |
| Lifecycle | Pause/resume, surface loss/recreation, process recreation, timing rebase, and held-input reset |
| Performance | Frame pacing, shader compilation, memory, module load time, thermal behavior, and battery impact |
| Accessibility | TalkBack traversal, labels, values, actions, state announcements, menus, and layout editor |
| Compatibility | 4 KB and 16 KB page sizes; documented minimum OS and supported ABI/device boundary |

## Principal risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| ModernGekko Android platform integration is larger than expected | Medium | High | Isolate module proof first; use Dolphin's existing Android surface/JNI code as the implementation reference |
| Android build silently runs JitArm64 fallback instead of the AOT module | Medium | Critical to product claim | Require module validation, default fallback JIT off, and gate on StaticRecomp counters |
| Large native module causes slow builds, large APKs, or cold-load stalls | High | Medium to high | Measure in Phase 0/A; arm64-only preview, release optimization, symbols outside APK, no premature ABI expansion |
| GLES driver differences expose rendering faults | Medium | High | Physical Adreno/Mali proof; keep Vulkan as a measured fallback, not parallel initial work |
| Surface recreation leaves stale `ANativeWindow` state or duplicate runtimes | Medium | High | Single runtime owner, pause-before-release, presenter surface replacement, repeated lifecycle tests |
| StaticRecomp timing/audio behavior differs under Android scheduling | Medium | High | Long-form music/voice/gameplay evidence and runtime counters before UI parity work |
| OpenSL ES latency or routing is inadequate | Medium | Medium | Measure first; add Oboe/AAudio only behind the existing sound-stream boundary if needed |
| Content URI is treated as a normal path or remains provider-dependent | Medium | High | Stream once to same-volume private staging, validate fully, then atomically activate |
| Touch parity is underestimated | High | High | Treat the Apple overlay behavior list as the product specification and phase it after controller proof |
| In-place update or reimport loses game data, saves, or settings | Low to medium | Critical | Same-volume staged swap, recovery markers, explicit backups during testing, byte-level preservation checks |
| Native libraries fail on 16 KB page-size devices | Medium | High | Modern pinned NDK/AGP, flexible-page build, inspect every ELF/APK, 16 KB emulator gate |
| Full Dolphin Android frontend leaks into the product scope | Medium | Medium | Build a thin SunPad JNI/app target and support only GMSE01 |
| Release package includes protected or private material | Low | Critical | Android package audit equivalent to the IPA audit; verify from the final downloadable artifact |

## Scope controls

The first Android release should deliberately avoid:

- a general-purpose GameCube loader or full Dolphin game browser;
- on-device DolRecomp, C compilation, or downloaded executable modules;
- a second copy of game or runtime logic maintained as an Android fork;
- enabling PowerPC JitArm64 fallback by default merely because Android permits
  executable memory;
- Vulkan and OpenGL ES implementation in parallel before the first proof;
- an audio-backend rewrite before OpenSL ES is measured;
- 32-bit ARM or x86 product ABIs;
- broad external-storage permissions or direct long-term execution from a
  document-provider URI;
- literal UIKit-to-Kotlin class translation;
- committing generated module sources, native products, retail media, saves,
  logs, keystores, or signing credentials; and
- Play Store work before a sideloaded APK passes physical acceptance.

These boundaries keep the first investment focused on the real uncertainty:
the ModernGekko Android host and physical runtime behavior.

## Recommendation

Proceed with Phase 0 and Phase A if community demand justifies two to four
focused engineering weeks. The project has enough upstream Android foundation
and enough portable SunPad architecture to make a successful proof likely.

Do not promise Android parity before the controller proof. The correct public
description is:

> Android is technically feasible and can be built from the existing macOS
> toolchain. The AOT-recompiled game module transfers; the real work is an
> Android ModernGekko host, mobile UI/storage integration, and physical-device
> validation.

The likely result is a real Android SunPad build, not streaming and not a
separate emulator package. The honest project label is **medium-to-large
platform port**, with a small bounded technical proof as the first go/no-go
investment.

## Sources

Repository and pinned-source evidence:

- [`scripts/ios-build-core-device.sh`](../scripts/ios-build-core-device.sh) -
  current separate core/module cross-build shape
- [`apple/ios/SunPadCoreHost.mm`](../apple/ios/SunPadCoreHost.mm) - runtime
  configuration, module loading, input pipe, lifecycle, and audio ownership
- [`apple/ios/SunPadDiscExtractor.mm`](../apple/ios/SunPadDiscExtractor.mm) -
  current DiscIO extraction wrapper
- [`apple/ios/SunPadGameViewController.mm`](../apple/ios/SunPadGameViewController.mm) -
  current staged import, validation, storage, and boot contract
- [`apple/ios/SunPadGameOverlay.mm`](../apple/ios/SunPadGameOverlay.mm) - touch,
  menu, settings, editing, and accessibility behavior to reproduce
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) - current execution and platform
  layering
- [`docs/LEGAL_AND_PROVENANCE.md`](LEGAL_AND_PROVENANCE.md) - distribution and
  user-data boundary
- [`docs/TESTING.md`](TESTING.md) - Apple runtime evidence and acceptance model
- [ModernGekko at the pinned source](https://github.com/ExpansionPak/ModernGekko/tree/048c426ba3db0369e40826d22ad3adcce7fe7c58)
- [Vendored RecompCore/Dolphin at the pinned source](https://github.com/ExpansionPak/RecompCore/tree/e13ab348f13cd67879f6db6e9d7185410f8f62c6)
- [DolRecomp at the pinned source](https://github.com/ExpansionPak/DolRecomp/tree/93b881c8f73df1d64a88491f2aa50c7c9ed2384d)

Android primary documentation:

- [Android NDK CMake guide](https://developer.android.com/ndk/guides/cmake)
- [Android ABI guide](https://developer.android.com/ndk/guides/abis)
- [Android native-window API](https://developer.android.com/ndk/reference/group/a-native-window)
- [Storage Access Framework documents guide](https://developer.android.com/training/data-storage/shared/documents-files)
- [App-specific storage guide](https://developer.android.com/training/data-storage/app-specific)
- [Android controller actions](https://developer.android.com/games/sdk/game-controller/controller-input)
- [Android high-performance audio](https://developer.android.com/ndk/guides/audio)
- [Android 16 KB page-size support](https://developer.android.com/guide/practices/page-sizes)
- [Google Play target API policy](https://support.google.com/googleplay/android-developer/answer/11926878)
