#!/usr/bin/env bash
# Builds Keyline and packages it as a DMG in build/dist.
#
#   scripts/make-dmg.sh            Test build: Release configuration, signed for development
#                                  (only runs on Macs in the development profile), not
#                                  notarized. Uses the development Network Extension
#                                  entitlement value.
#
# Developer ID signing and notarization for public releases come with the release pipeline
# (docs/PLAN.md, phase 6).
#
# The build number is the git commit count, so every DMG is newer than the last and macOS
# replaces the installed VPN component.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$repo_root/build/DerivedData-dmg"
dist="$repo_root/build/dist"
command -v create-dmg >/dev/null || { echo "error: create-dmg missing; run: brew install create-dmg" >&2; exit 1; }

[[ -d "$repo_root/build/core/Tun2socks.xcframework" ]] || "$repo_root/core/build-xcframework.sh"

build_number="$(git -C "$repo_root" rev-list --count HEAD)"
echo "building Keyline (build $build_number)…"
xcodebuild build \
  -project "$repo_root/Keyline.xcodeproj" \
  -scheme Keyline \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$build_number" \
  KEYLINE_NE_PROVIDER=packet-tunnel-provider \
  | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)' | grep -v appintents || true

app="$derived_data/Build/Products/Release/Keyline.app"
[[ -d "$app" ]] || { echo "error: build failed, no $app" >&2; exit 1; }
codesign --verify --deep --strict "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="$dist/Keyline-$version-$build_number-test.dmg"
mkdir -p "$dist"
rm -f "$dmg"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Keyline.app"

create-dmg \
  --volname "Keyline $version" \
  --volicon "$app/Contents/Resources/AppIcon.icns" \
  --window-pos 200 160 \
  --window-size 560 340 \
  --icon-size 112 \
  --icon "Keyline.app" 150 160 \
  --hide-extension "Keyline.app" \
  --app-drop-link 410 160 \
  --no-internet-enable \
  "$dmg" "$staging" >/dev/null

hdiutil verify -quiet "$dmg"
echo "$dmg"
