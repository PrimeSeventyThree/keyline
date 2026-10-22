#!/usr/bin/env bash
# Builds Tun2socks.xcframework (macOS, arm64 + x86_64) from the upstream Outline Go core
# in third_party/outline-apps. Mirrors the `apple` task in client/go/Taskfile.yml, but
# targets plain macOS instead of Mac Catalyst.
#
# Usage: core/build-xcframework.sh [output-dir]   (default: build/core)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
upstream="$repo_root/third_party/outline-apps"
out_dir="${1:-$repo_root/build/core}"
bin_dir="$repo_root/build/tools"

# Go 1.25 is what upstream ships and the last line known to support macOS 12.
# Resolve that toolchain up front and put it first on PATH, so gomobile's nested `go`
# calls use it directly (newer go launchers abort on the GODEBUG value set below).
go_version="${KEYLINE_GO_VERSION:-go1.25.14}"
go_root="$(cd "$repo_root" && GOTOOLCHAIN="$go_version" go env GOROOT)"
export PATH="$go_root/bin:$PATH" GOTOOLCHAIN=local
# Must match MACOSX_DEPLOYMENT_TARGET in Keyline.xcodeproj.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
# Workaround from upstream: https://github.com/golang/go/issues/71827#issuecomment-2669425491
export GODEBUG=gotypesalias=0
# Keep native debug info so crash reports in the bound library can be symbolicated.
export CGO_CFLAGS='-fstack-protector-strong -g'

[[ -f "$upstream/go.mod" ]] || { echo "error: submodule missing; run: git submodule update --init" >&2; exit 1; }

mkdir -p "$bin_dir"
# Build gomobile/gobind at the x/mobile version pinned by upstream's go.mod.
(cd "$upstream" && go build -o "$bin_dir" golang.org/x/mobile/cmd/gomobile golang.org/x/mobile/cmd/gobind)

rm -rf "$out_dir/Tun2socks.xcframework"
mkdir -p "$out_dir"
cd "$upstream"
PATH="$bin_dir:$PATH" "$bin_dir/gomobile" bind \
  -target=macos \
  -bundleid ca.pulsbeat.keyline.tun2socks \
  -o "$out_dir/Tun2socks.xcframework" \
  ./client/go/outline/platerrors ./client/go/outline/tun2socks ./client/go/outline

echo "built: $out_dir/Tun2socks.xcframework (go: $(go version | awk '{print $3}'), macOS >= $MACOSX_DEPLOYMENT_TARGET)"
