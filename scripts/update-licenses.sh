#!/usr/bin/env bash
# Copies the licence texts shown in Settings › About › Licenses into Resources/Licenses.
# Files are named license-<order>-<name>.txt; the app lists them in that order.
# (flag-icons' licence is written by scripts/import-flags.sh.)
#
# Usage: scripts/update-licenses.sh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out="$repo_root/Resources/Licenses"
mkdir -p "$out"

cp "$repo_root/NOTICE" "$out/license-1-keyline-notice.txt"
cp "$repo_root/LICENSE" "$out/license-2-apache-2.0.txt"
cp "$repo_root/Resources/GeoIP/SOURCE.txt" "$out/license-4-db-ip.txt"

# The Go core's dependencies and the Go runtime, which are compiled into the app.
upstream="$repo_root/third_party/outline-apps"
go_root="$(cd "$repo_root" && GOTOOLCHAIN="${KEYLINE_GO_VERSION:-go1.25.14}" go env GOROOT)"
export PATH="$go_root/bin:$PATH" GOTOOLCHAIN=local GOOS=darwin
go_licenses="github.com/google/go-licenses@v1.6.0"
packages=(./client/go/outline/... ./client/go/outline/tun2socks)
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
(cd "$upstream" && go run "$go_licenses" save "${packages[@]}" --ignore localhost --save_path "$work/licenses" 2>/dev/null)
(cd "$upstream" && go run "$go_licenses" report "${packages[@]}" --ignore localhost 2>/dev/null) | sort -u > "$work/report.csv"

{
  echo "Keyline includes the following Go modules, compiled into its network core."
  echo
  while IFS=, read -r module url license; do
    echo "== $module ($license)"
    echo "$url"
    echo
    find "$work/licenses/$module" -maxdepth 1 -type f \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' \) \
      -exec cat {} \; 2>/dev/null
    echo
  done < "$work/report.csv"
  # go-tun2socks bundles the lwIP TCP/IP stack as C source; its licence is in each file's
  # header comment rather than a licence file.
  lwip="$(cd "$upstream" && go env GOMODCACHE)/$(cd "$upstream" && go list -m -f '{{.Path}}@{{.Version}}' github.com/eycorsican/go-tun2socks)/core/c/core/memp.c"
  echo "== lwIP, included in github.com/eycorsican/go-tun2socks (BSD-3-Clause)"
  echo "https://savannah.nongnu.org/projects/lwip/"
  echo
  # From the first "Copyright" line to the end of that comment.
  awk '/Copyright/ { on = 1 } on { print } on && /\*\// { exit }' "$lwip"
  echo
  echo "== The Go programming language (BSD-3-Clause)"
  echo "https://go.dev/LICENSE"
  echo
  cat "$go_root/LICENSE"
} > "$out/license-5-go-modules.txt"

echo "$(wc -l < "$work/report.csv" | tr -d ' ') Go modules"
ls "$out"
