#!/usr/bin/env bash
# Runs the unit tests. Builds the Go core first if it is missing.
#
# Build products go to the internal disk (KEYLINE_DERIVED_DATA, default below): when the
# repo lives on an external volume, the test runner xcodebuild launches can't load test
# bundles from there.
#
# Usage: scripts/test.sh [extra xcodebuild arguments], e.g. CODE_SIGNING_ALLOWED=NO on CI
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${KEYLINE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Keyline-cli}"

[[ -d "$repo_root/build/core/Tun2socks.xcframework" ]] || "$repo_root/core/build-xcframework.sh"

xcodebuild test \
  -project "$repo_root/Keyline.xcodeproj" \
  -scheme Keyline \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  "$@"
