#!/usr/bin/env bash
# Checks that Keyline.xcodeproj is exactly what project.yml generates, so the spec and the
# checked-in project can't drift apart. Runs in CI on every pull request.
#
# Uses XcodeGen $xcodegen_version (below): other versions write slightly different project files.
# If the xcodegen on PATH is another version, the pinned one is downloaded to build/tools.
# The working copy's project is compared and then put back, so running this changes nothing.
#
# Usage: scripts/check-project.sh
set -euo pipefail

xcodegen_version="2.46.0"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
project="$repo_root/Keyline.xcodeproj"

xcodegen="$(command -v xcodegen || true)"
if [[ -z "$xcodegen" || "$("$xcodegen" --version | awk '{print $2}')" != "$xcodegen_version" ]]; then
  xcodegen="$repo_root/build/tools/xcodegen-$xcodegen_version/bin/xcodegen"
  if [[ ! -x "$xcodegen" ]]; then
    echo "Downloading XcodeGen $xcodegen_version"
    download="$(mktemp -d)"
    curl -sSfL "https://github.com/yonaskolb/XcodeGen/releases/download/$xcodegen_version/xcodegen.zip" -o "$download/xcodegen.zip"
    unzip -q "$download/xcodegen.zip" -d "$download"
    mkdir -p "$(dirname "$(dirname "$xcodegen")")"
    rm -rf "$repo_root/build/tools/xcodegen-$xcodegen_version"
    mv "$download/xcodegen" "$repo_root/build/tools/xcodegen-$xcodegen_version"
    rm -rf "$download"
  fi
fi

saved="$(mktemp -d)"
cp -R "$project" "$saved/"
trap 'rm -rf "$project" && mv "$saved/Keyline.xcodeproj" "$project" && rm -rf "$saved"' EXIT

(cd "$repo_root" && "$xcodegen" generate --quiet)
if ! diff -r -q "$saved/Keyline.xcodeproj" "$project" >/dev/null; then
  echo "error: Keyline.xcodeproj doesn't match project.yml. Run 'xcodegen generate' (XcodeGen $xcodegen_version) and commit both." >&2
  diff -r -u "$saved/Keyline.xcodeproj" "$project" | head -60 >&2 || true
  exit 1
fi
echo "Keyline.xcodeproj matches project.yml (XcodeGen $xcodegen_version)"
