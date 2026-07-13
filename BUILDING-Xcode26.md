# Building OpenEmu 2.4.1 on Xcode 26 (Phase 0 baseline)

This snapshot is OpenEmu **v2.4.1** (matches the upstream `v2.4.1` tag exactly).
It originally targeted an older Xcode/toolchain. These notes capture what was
needed to get a clean **app build** on **Xcode 26.5** (build 17F42), arm64.

## 1. Restore git + submodules

The snapshot shipped without a `.git` directory and with all submodules empty.
Reconstructed in place against the upstream tag:

```sh
git init
git remote add origin https://github.com/OpenEmu/OpenEmu.git
git fetch --depth 1 origin tag v2.4.1
git reset v2.4.1            # restores HEAD/index/.gitmodules; working tree untouched
```

App-critical submodules (the ~25 emulator cores are NOT needed for the app shell):

```sh
git submodule update --init OpenEmuKit OpenEmu-SDK OpenEmu-Shaders \
    Vendor/XADMaster Vendor/UniversalDetector
# OpenEmu-Shaders nests SwiftSPIRV-Cross, which itself nests SPIRV-Tools/Cross/glslang:
git -C OpenEmu-Shaders submodule update --init --recursive 3rdparty/SPIRV
```

## 2. Install the Metal toolchain

Xcode 26 ships the Metal compiler as a separate on-demand component (~688 MB):

```sh
xcodebuild -downloadComponent MetalToolchain
```

## 3. Source fix (committed)

`OpenEmu-SDK/OpenEmuSystem/OESwitchProControllerHIDDeviceHandler.m`
The `OEHACUSBAcknowledgmentOutputReport.reportID` field was typed as the *output*
report enum but is only ever compared to an *input* report ID
(`OEHACInputReportIDUSBSubcommandReply`). Newer clang promotes the resulting
`-Wenum-compare` to an error under `-Werror`. Field retyped to `OEHACInputReportID`
(semantically correct — the ACK is a received/input report; both enums are
`uint8_t`-backed so runtime behavior is identical).

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
  build          # or: build-for-testing
```

### Why the two build-setting overrides

- `VERSIONING_SYSTEM=""` — the vendored `CSPIRVTools` target (in the SwiftSPIRV-Cross
  submodule) uses `apple-generic` versioning. The generated `CSPIRVTools_vers.c`
  compile and the `module.modulemap` copy form a dependency cycle that Xcode 26's
  build system rejects ("Cycle inside CSPIRVTools"). Disabling generated versioning
  removes the offending node. (Versioning symbols in a static C lib are unused here.)
- `SWIFT_ENABLE_EXPLICIT_MODULES=NO` — Xcode 26 builds Swift modules explicitly by
  default. `OpenEmuKit`'s public `.swiftmodule` references its private Clang module
  `OpenEmuKitPrivate`, which consumers (`broker`, `OpenEmuHelperApp`) can't resolve
  under explicit modules. Reverting to implicit modules restores the 2.4.1 behavior.

These two are currently passed on the command line (no project files edited besides
the source fix in §3). To make them permanent, bake them into an `.xcconfig` or the
relevant target build settings — see Phase 0 follow-ups.

## Status

- `** BUILD SUCCEEDED **` — produces `OpenEmu.app` (+ `OpenEmuHelperApp`, `broker`).
- `** TEST BUILD SUCCEEDED **` — produces `OpenEmuTests.xctest`.
- Not yet done: code-signing + launching the app, and actually *running* the test
  suite (the hosted tests need the app to launch, which requires signing).
