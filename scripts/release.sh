#!/usr/bin/env bash
# Builds a Keyline release: signed with Developer ID, notarized and stapled, as a DMG with a
# Sparkle appcast, in build/release/<tag>.
#
# Usage: scripts/release.sh <version> [--tag <tag>] [--publish]
#   <version>   marketing version, such as 0.1.0 (the build number is the git commit count)
#   --tag       git tag and GitHub release name (default: v<version>); a tag with "-", such as
#               v0.1.0-beta.1, is published as a prerelease
#   --publish   also create the GitHub release with the DMG and appcast.xml
#
# Needs, on this Mac:
#   - the "Developer ID Application: Pulsbeat Media Inc. (49DY4CP2B4)" certificate
#   - the notarytool keychain profile "keyline-notary" (KEYLINE_NOTARY_PROFILE to override)
#   - the Sparkle EdDSA key in the login keychain (generate_keys --account keyline)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:?usage: scripts/release.sh <version> [--tag <tag>] [--publish]}"
shift
tag="v$version"
publish=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) tag="$2"; shift 2 ;;
    --publish) publish=true; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

team="49DY4CP2B4"
identity="Developer ID Application: Pulsbeat Media Inc. ($team)"
notary_profile="${KEYLINE_NOTARY_PROFILE:-keyline-notary}"
repo_url="https://github.com/PrimeSeventyThree/keyline"
out="$repo_root/build/release/$tag"
derived_data="${KEYLINE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Keyline-release}"
sparkle="$repo_root/build/tools/sparkle"
step() { printf '\n==> %s\n' "$*"; }

[[ -z "$(git -C "$repo_root" status --porcelain --untracked-files=no)" ]] \
  || { echo "error: commit your changes first; releases are built from committed code" >&2; exit 1; }
security find-identity -v -p codesigning | grep -q "$identity" \
  || { echo "error: \"$identity\" is not in the keychain" >&2; exit 1; }
[[ -d "$repo_root/build/core/Tun2socks.xcframework" ]] || "$repo_root/core/build-xcframework.sh"
if [[ ! -x "$sparkle/bin/generate_appcast" ]]; then
  mkdir -p "$sparkle"
  curl -sSfL "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz" | tar -xJ -C "$sparkle"
fi

build_number="$(git -C "$repo_root" rev-list --count HEAD)"
rm -rf "$out"
mkdir -p "$out"

step "Archiving Keyline $version ($build_number)"
# The Release configuration signs automatically with the Developer ID certificate, so Xcode uses
# its Developer ID ("Mac Team Direct") profiles, which grant the -systemextension NE values.
xcodebuild archive \
  -project "$repo_root/Keyline.xcodeproj" -scheme Keyline -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived_data" \
  -archivePath "$out/Keyline.xcarchive" -allowProvisioningUpdates \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
  | grep -E 'error:|warning: .*(sign|profile|entitle)|ARCHIVE (SUCCEEDED|FAILED)' || true
[[ -d "$out/Keyline.xcarchive" ]] || { echo "error: archive failed" >&2; exit 1; }

step "Exporting with Developer ID"
cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>$team</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$out/Keyline.xcarchive" -exportPath "$out/export" \
  -exportOptionsPlist "$out/ExportOptions.plist" -allowProvisioningUpdates \
  | grep -E 'error:|EXPORT (SUCCEEDED|FAILED)' || true
app="$out/export/Keyline.app"
[[ -d "$app" ]] || { echo "error: export failed" >&2; exit 1; }

step "Checking signatures and entitlements"
codesign --verify --deep --strict "$app"
tunnel="$app/Contents/Library/SystemExtensions/ca.pulsbeat.keyline.tunnel.systemextension"
for bundle in "$app" "$tunnel" "$app/Contents/Library/LoginItems/KeylineLoginHelper.app"; do
  codesign -dvv "$bundle" 2>&1 | grep -q "Authority=$identity" \
    || { echo "error: $(basename "$bundle") is not signed with $identity" >&2; exit 1; }
done
for bundle in "$app" "$tunnel"; do
  codesign -d --entitlements :- "$bundle" 2>/dev/null | grep -q "packet-tunnel-provider-systemextension" \
    || { echo "error: $(basename "$bundle") lacks the Developer ID Network Extension entitlement" >&2; exit 1; }
done

step "Notarizing the app"
ditto -c -k --keepParent "$app" "$out/Keyline.zip"
xcrun notarytool submit "$out/Keyline.zip" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app"
rm "$out/Keyline.zip"

step "Building the DMG"
dmg_dir="$out/dmg"
mkdir -p "$dmg_dir"
dmg="$dmg_dir/Keyline-$version.dmg"
staging="$(mktemp -d)"
ditto "$app" "$staging/Keyline.app"
create-dmg \
  --volname "Keyline $version" --volicon "$app/Contents/Resources/AppIcon.icns" \
  --window-pos 200 160 --window-size 560 340 --icon-size 112 \
  --icon "Keyline.app" 150 160 --hide-extension "Keyline.app" --app-drop-link 410 160 \
  --no-internet-enable "$dmg" "$staging" >/dev/null
rm -rf "$staging"
codesign --sign "$identity" --timestamp "$dmg"

step "Notarizing the DMG"
xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

step "Writing the Sparkle appcast"
"$sparkle/bin/generate_appcast" --account keyline \
  --download-url-prefix "$repo_url/releases/download/$tag/" \
  --link "$repo_url" -o "$out/appcast.xml" "$dmg_dir"
grep -q 'sparkle:edSignature' "$out/appcast.xml" || { echo "error: appcast is not signed" >&2; exit 1; }

echo
echo "Release ready in $out:"
echo "  $(basename "$dmg")  (notarized, stapled)"
echo "  appcast.xml"

if $publish; then
  step "Publishing $tag on GitHub"
  prerelease=()
  [[ "$tag" == *-* ]] && prerelease=(--prerelease)
  gh release create "$tag" "${prerelease[@]}" --repo PrimeSeventyThree/keyline \
    --target "$(git -C "$repo_root" rev-parse HEAD)" --title "Keyline $version ($tag)" \
    --generate-notes "$dmg" "$out/appcast.xml"
fi
