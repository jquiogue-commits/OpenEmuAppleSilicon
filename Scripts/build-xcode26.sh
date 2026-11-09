#!/bin/sh
#
# Build the OpenEmu app shell on Xcode 26 with the toolchain-compat overrides
# required by the 2.4.1 baseline. See BUILDING-Xcode26.md for the rationale.
#
# Usage:
#   Scripts/build-xcode26.sh [action] [extra xcodebuild args...]
#     action defaults to "build"; pass "build-for-testing", "clean", etc.
#
# Prereqs (one-time): submodules checked out + `xcodebuild -downloadComponent MetalToolchain`.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACTION="${1:-build}"
[ $# -gt 0 ] && shift

exec xcodebuild \
  -workspace "$ROOT/OpenEmu.xcworkspace" \
  -scheme OpenEmu \
  -configuration Debug \
  -derivedDataPath "${DERIVED_DATA:-/tmp/oe-dd}" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  VERSIONING_SYSTEM="" \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  GCC_TREAT_WARNINGS_AS_ERRORS=NO \
  MACOSX_DEPLOYMENT_TARGET=12.0 \
  "$@" \
  "$ACTION"
