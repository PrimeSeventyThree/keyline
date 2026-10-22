#!/usr/bin/env bash
# Renders the design snapshots (Tests/Snapshots.swift) to PNG files.
#
# Usage: scripts/snapshots.sh [output-dir] [extra xcodebuild arguments]
#        (default output: build/snapshots)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="$repo_root/build/snapshots"
if [[ $# -gt 0 && "$1" != -* ]]; then out_dir="$1"; shift; fi
mkdir -p "$out_dir" && out_dir="$(cd "$out_dir" && pwd)"

# The test runner may not write to external volumes, so render on the internal disk first.
render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT

# xcodebuild passes TEST_RUNNER_-prefixed variables to the test process without the prefix.
TEST_RUNNER_KEYLINE_SNAPSHOT_DIR="$render_dir" "$repo_root/scripts/test.sh" -only-testing:KeylineTests/Snapshots "$@"
cp "$render_dir"/*.png "$out_dir"/
echo "snapshots in $out_dir"
