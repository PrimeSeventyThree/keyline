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
ls "$out"
