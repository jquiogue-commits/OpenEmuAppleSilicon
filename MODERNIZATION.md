# OpenEmu 2.4.1 — Modernization

This fork takes the OpenEmu **2.4.1** source snapshot and modernizes it to build and
run on **Xcode 26.5 / Apple Silicon**, then progressively updates the codebase:
Objective-C → Swift ports, a unified macOS deployment floor, retirement of a legacy
UI stack, async/await adoption for the networking paths, and selective SwiftUI for
leaf views.

The work is organized into phases, each landing as its own commit on top of the
`Set version 2.4.1` baseline. Every phase builds green, and most were validated by
running the app against an isolated test library (never the user's real one).

## Environment

- **Xcode:** built on 26.5; currently verified on **27.2**, arm64
- **Deployment floor:** **macOS 12.0 (Monterey)**, unified across all app targets
  (raised from 11.5 — see [Toolchain update](#toolchain-update-xcode-272--macos-120-floor))
- **Swift:** 5.0 language mode

## Building

See [`BUILDING-Xcode26.md`](BUILDING-Xcode26.md) for the full reconstruction recipe
(submodules, Metal toolchain). The convenience wrapper is:

```sh
Scripts/build-xcode26.sh build
```

It invokes `xcodebuild` with the required overrides (`VERSIONING_SYSTEM=""` to break a
CSPIRVTools build cycle, `SWIFT_ENABLE_EXPLICIT_MODULES=NO` for OpenEmuKitPrivate module
resolution, ad-hoc/no code signing, `-derivedDataPath /tmp/oe-dd`).

## What was done

| Phase | Summary |
|-------|---------|
| **0** | Xcode 26.5 build baseline + tooling (build wrapper, docs, SwiftPM pin). |
| **1** | Unify the macOS deployment floor to 11.5; remove dead `@available`/`#available` code and Catalina-era workarounds. |
| **2** | Port self-contained Objective-C clusters to Swift (Core Data migrators, file/audio utilities, and **every** system controller + responder — 27 controllers, 42 responders). |
| **3** | Retire the legacy `OEGridView`/`IKImageBrowser` games grid (~3,600 LOC) onto the modern `NSCollectionView` stack; finish its list view; retire the legacy media view controllers. |
| **4** | Convert the networking/download paths to async/await (`Download`, OpenVGDB self-update, CoreUpdater core-list/appcast fetches, shader download). |
| **5** | Reimplement two leaf preference panes (Gameplay, System Files) in SwiftUI, hosted in the AppKit preferences window via `NSHostingView`. |

### Phase 0 — Build baseline

Reconstructs a buildable project on Xcode 26.5: the build wrapper
(`Scripts/build-xcode26.sh`), the [`BUILDING-Xcode26.md`](BUILDING-Xcode26.md) recipe,
and a SwiftPM resolution pin. Three changes were needed to compile: an enum-comparison
fix in `OpenEmu-SDK` (see caveats below), and two build-setting overrides carried on the
command line.

### Phase 1 — macOS 11.5 floor + dead-code cleanup

All deployment targets consolidated to macOS 11.5. Removed ~47 always-true `#available`
runtime guards (keeping the true branch, dropping dead fallbacks), redundant `@available`
attributes across ~25 files, and Category-C dead code (a Catalina background-dimming
workaround in `OESearchField`, an unused completion-handler `ImageCacheService.fetchImage`
overload, and a dead `FileManager.legacyHashFile`).

### Phase 2 — Objective-C → Swift ports

Mechanical, behavior-preserving ports of self-contained clusters:

- **Core Data migration machinery:** `ALIterativeMigrator`, `OEVersionMigrationController`,
  and the `OEDB{Image,Rom,SaveState}MigrationPolicy` classes (the policies keep
  `@objc(BareName)` so `.xcmappingmodel` string references still resolve).
- **Support utilities:** `OEFileManager`, `OEAudioDeviceManager`, `NSDocument+OEAdditions`,
  `OELibraryDatabase`.
- **SystemPlugins:** every `OE*SystemController` and `OE*SystemResponder` is now Swift.
  Each plugin gained a bridging header, and its `Info.plist` `NSPrincipalClass` /
  `OEResponderClassKey` were rewritten to the module-qualified Swift names.

The only Objective-C intentionally left is `XADArchive+OE.m` — an exception shim
(`@try/@catch`) that Swift cannot replace, since Swift can't catch Objective-C exceptions.

### Phase 3 — Retire the legacy games grid

OpenEmu 2.4.1 shipped a legacy `IKImageBrowser`/`OEGridView` games grid alongside an
unfinished modern `NSCollectionView` stack (gated behind a debug flag). This phase
finished the modern stack's **list view** (table data source/delegate: sort, select,
inline rename, rating, context menu) and deleted the legacy cluster — 13 files, ~3,600 LOC
(`OEGameCollectionViewController`, `OECollectionViewController`, `OEGridView`,
`OEGridGameCell`, `OEGridCell`, plus the `OEMediaViewController` media cluster). The modern
controller is now the sole path. A layout bug was found and fixed along the way (the
runtime-loaded list scroll view rendered its header under the toolbar).

### Phase 4 — async/await for networking

The download/update paths were converted from delegate + completion-handler + blocking
semaphore designs to `async`/`await`, bridging the delegate-based `URLSession` APIs to
`CheckedContinuation` (the built-in async `URLSession.data/download(for:)` is macOS 12+,
above this fork's floor):

- **`Download`** → `func download(progressHandler:) async throws -> URL` (dropped the
  blocking `DispatchSemaphore`); 3 call sites updated to `Task { await }`.
- **OpenVGDB** self-update → async; deleted its bespoke `URLSessionDownloadDelegate` in
  favor of the shared async `Download`.
- **CoreUpdater** appcast + core-list fetches → async.
- The shader-download debug action → async.

No blocking waits remain in the codebase. The `CoreDownload` core-installer and the
`ROMImporter`/`ImportOperation` pipeline were deliberately left as larger, separate efforts.

### Phase 5 — Selective SwiftUI

Two self-contained preference panes were reimplemented in SwiftUI and hosted in the
existing AppKit preferences window via `NSHostingView` (the `PreferencePane` protocol
conformance is unchanged, so the window/toolbar host them as before):

- **Gameplay** — six window-management toggles bound with `@AppStorage`, plus a shader
  `Picker` backed by an `ObservableObject` mirroring `OEShaderStore`.
- **System Files (BIOS)** — a `List` of per-core required BIOS files with availability
  indicators, a context-menu delete, and drop-to-import.

Kept to macOS 11.5-safe SwiftUI (`@AppStorage`/`@StateObject` are 11.0+; avoided
`.formStyle`/`LabeledContent`/`@FocusState`, which are 12–13+).

## Toolchain update: Xcode 27.2 / macOS 12.0 floor

Phases 0–5 were done against Xcode 26.5 with an 11.5 floor (the phase notes above describe
that state and are left as written). Xcode 27.2 no longer supports deployment targets
below 12.0, so the whole project failed to build on it. The fix:

- **Floor raised to 12.0** in the app project (all 8 settings). The submodule projects
  (OpenEmu-SDK, OpenEmuKit, OpenEmu-Shaders, SPIRV) set 10.14/10.14.4 themselves, so the
  build wrapper passes `MACOSX_DEPLOYMENT_TARGET=12.0` rather than editing submodules.
- **`OpenEmuKit` submodule advanced** from `2bc0ee9` to upstream `b04276c`, which contains
  the upstream "Fix building for Xcode 27.0" change. At a 12.0 target the old pinned
  revision hit a hard error: its `else` branch (macOS < 11 only) referenced `GameAudio`,
  which is marked obsolete from 11.0. No fork or local patch is needed.
- **Metal toolchain** must be re-installed per Xcode (`xcodebuild -downloadComponent MetalToolchain`).

With the floor at 12.0, the async `URLSession.data/download(for:)` APIs are now available,
so the continuation bridges added in Phase 4 *could* be simplified. They still work and
were left alone to keep this change minimal.

## Reproducibility

This fork clones and builds without any submodule edits:

- **`.gitmodules` uses absolute upstream URLs**, so `git submodule update --init …`
  resolves against the real OpenEmu/MacPaw repos from a fresh clone.
- **No SDK patch is required.** A latent `-Wenum-compare` in the upstream OpenEmu-SDK
  (which newer clang treats as a `-Werror` failure) is handled by passing
  `GCC_TREAT_WARNINGS_AS_ERRORS=NO` in the build wrapper, so the unmodified submodule
  compiles. See [`BUILDING-Xcode26.md`](BUILDING-Xcode26.md) §3.

## Deferred / not yet done

- The `CoreDownload` core-installer async conversion, and the
  `ROMImporter`/`ImportOperation` import pipeline (larger efforts).
- Further SwiftUI leaves (Cores / Library panes, the `NameShaderPreset` dialog).
- The 42 `SystemResponder` ports are compiler-verified only — not yet play-tested with a
  running core; the PSP `.cso` path was likewise never tested against a real sample.

The redundant legacy `OESaveStateQLPlugin.qlgenerator` target has now been removed
(superseded by the modern `OpenEmuQLThumbnail`/`OpenEmuQLPreview` app extensions on the
11.5+ floor).
