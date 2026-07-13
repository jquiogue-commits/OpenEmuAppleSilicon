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

- **Xcode:** 26.5, arm64
- **Deployment floor:** macOS 11.5 (Big Sur), unified across all app targets
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

## Known limitations

- **The Phase 0 SDK fix is not committed here.** The `OESwitchProController` enum-comparison
  fix lives in the `OpenEmu-SDK` submodule's worktree and was never committed to the
  submodule, so a fresh clone won't have it.
- **Submodule URLs are relative** (`../../OpenEmu/*.git`) and won't resolve against this
  fork; a `--recursive` clone needs the submodules initialized from upstream OpenEmu.
- **Deferred:** the `CoreDownload` core-installer async conversion, the
  `ROMImporter`/`ImportOperation` import pipeline, further SwiftUI leaves, and removal of
  the redundant legacy `OESaveStateQLPlugin.qlgenerator` (superseded by the modern
  `OpenEmuQLThumbnail`/`OpenEmuQLPreview` extensions on the 11.5+ floor).
