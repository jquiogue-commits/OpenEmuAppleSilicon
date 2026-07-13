# Building OpenEmu 2.4.1 on Xcode 26 (Phase 0 baseline)

This snapshot is OpenEmu **v2.4.1** (matches the upstream `v2.4.1` tag exactly).
It originally targeted an older Xcode/toolchain. These notes capture what was
needed to get a clean **app build** on **Xcode 26.5** (build 17F42), arm64.

## 1. Clone + submodules

This fork's `.gitmodules` uses absolute upstream URLs, so a fresh clone resolves
submodules directly. Only the app-critical submodules are needed (the ~25 emulator
cores are NOT required for the app shell):

```sh
git clone https://github.com/jquiogue-commits/OpenEmuAppleSilicon.git
cd OpenEmuAppleSilicon
git submodule update --init OpenEmuKit OpenEmu-SDK OpenEmu-Shaders \
    Vendor/XADMaster Vendor/UniversalDetector
# OpenEmu-Shaders nests SwiftSPIRV-Cross, which itself nests SPIRV-Tools/Cross/glslang:
git -C OpenEmu-Shaders submodule update --init --recursive 3rdparty/SPIRV
```

(For historical reference, the original snapshot shipped without a `.git` directory and
was reconstructed against the upstream `v2.4.1` tag via `git init` + `git fetch --depth 1
origin tag v2.4.1` + `git reset v2.4.1`.)

## 2. Install the Metal toolchain

Xcode 26 ships the Metal compiler as a separate on-demand component (~688 MB):

```sh
xcodebuild -downloadComponent MetalToolchain
```

## 3. Warnings-as-errors relaxed (no submodule patch needed)

Newer clang promotes a latent `-Wenum-compare` in the **upstream** OpenEmu-SDK
(`OpenEmuSystem/OESwitchProControllerHIDDeviceHandler.m` — the
`OEHACUSBAcknowledgmentOutputReport.reportID` field is typed as the *output* report
enum but only ever compared to an *input* report ID) to an error under `-Werror`.

Rather than patch the submodule (which would fork it or leave an uncommitted change),
the build wrapper passes `GCC_TREAT_WARNINGS_AS_ERRORS=NO`, so the **unmodified**
upstream SDK compiles. This keeps a fresh `git clone --recursive` of this fork building
with zero submodule edits. (The underlying retype — `OEHACInputReportID`, semantically
the ACK is a received/input report; both enums are `uint8_t`-backed — is a fine upstream
fix, but not required here.)

## 4. Build command (working)

Convenience wrapper (recommended): `Scripts/build-xcode26.sh [action]`
(defaults to `build`; pass `build-for-testing`, `clean`, etc.). It runs the
exact invocation below.

```sh
xcodebuild \
  -workspace OpenEmu.xcworkspace \
  -scheme OpenEmu \
  -configuration Debug \
  -derivedDataPath /tmp/oe-dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  VERSIONING_SYSTEM="" \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  GCC_TREAT_WARNINGS_AS_ERRORS=NO \
  build          # or: build-for-testing
```

### Why the three build-setting overrides

- `VERSIONING_SYSTEM=""` — the vendored `CSPIRVTools` target (in the SwiftSPIRV-Cross
  submodule) uses `apple-generic` versioning. The generated `CSPIRVTools_vers.c`
  compile and the `module.modulemap` copy form a dependency cycle that Xcode 26's
  build system rejects ("Cycle inside CSPIRVTools"). Disabling generated versioning
  removes the offending node. (Versioning symbols in a static C lib are unused here.)
- `SWIFT_ENABLE_EXPLICIT_MODULES=NO` — Xcode 26 builds Swift modules explicitly by
  default. `OpenEmuKit`'s public `.swiftmodule` references its private Clang module
  `OpenEmuKitPrivate`, which consumers (`broker`, `OpenEmuHelperApp`) can't resolve
  under explicit modules. Reverting to implicit modules restores the 2.4.1 behavior.
- `GCC_TREAT_WARNINGS_AS_ERRORS=NO` — lets the unmodified upstream OpenEmu-SDK compile
  (see §3); newer clang would otherwise reject a latent `-Wenum-compare` under `-Werror`.

These three are passed on the command line (no project or submodule files edited). To
make them permanent, bake them into an `.xcconfig` or the relevant target build settings.

## Status

- `** BUILD SUCCEEDED **` — produces `OpenEmu.app` (+ `OpenEmuHelperApp`, `broker`).
- `** TEST BUILD SUCCEEDED **` — produces `OpenEmuTests.xctest`.
- Not yet done: code-signing + launching the app, and actually *running* the test
  suite (the hosted tests need the app to launch, which requires signing).
