#!/usr/bin/env bash
# Builds a Keyline release: signed with Developer ID, notarized and stapled, as a DMG with a
# Sparkle appcast, in build/release/<tag>.
#
# Usage: scripts/release.sh <version> [--tag <tag>] [--publish] [--since <ref>] [--yes]
#   <version>   marketing version, such as 0.1.0 (the build number is the git commit count)
#   --tag       git tag and GitHub release name (default: v<version>); a tag with "-", such as
#               v0.1.0-beta.1, is published as a prerelease
#   --publish   also create the GitHub release with the DMG, appcast.xml and release notes
#   --since     where the release notes start (default: the previous v* tag; see release-notes.sh)
#   --yes       use the release notes without stopping to review them
#
# The release notes (scripts/release-notes.sh) come first, so you can review and edit them
# before the long build and notarization.
#
# Needs, on this Mac:
#   - the "Developer ID Application: Pulsbeat Media Inc. (49DY4CP2B4)" certificate, and the
#     "Keyline Developer ID" and "Keyline Tunnel Developer ID" provisioning profiles (Developer
#     ID profiles can only be created by the Account Holder, at developer.apple.com)
#   - the notarytool keychain profile "keyline-notary" (KEYLINE_NOTARY_PROFILE to override)
#   - the Sparkle EdDSA key in the login keychain (generate_keys --account keyline); the script
#     exports it with generate_keys for signing, so no Keychain prompt appears
# macOS bash 3.2 treats an empty array as unbound under set -u, hence ${a[@]+"${a[@]}"} below.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:?usage: scripts/release.sh <version> [--tag <tag>] [--publish] [--since <ref>] [--yes]}"
shift
tag="v$version"
publish=false
review=true
notes_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) tag="$2"; shift 2 ;;
    --publish) publish=true; shift ;;
    --since) notes_args=(--since "$2"); shift 2 ;;
    --yes) review=false; shift ;;
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
identities="$(security find-identity -v -p codesigning)"
[[ "$identities" == *"$identity"* ]] || { echo "error: \"$identity\" is not in the keychain" >&2; exit 1; }
[[ -d "$repo_root/build/core/Tun2socks.xcframework" ]] || "$repo_root/core/build-xcframework.sh"
if [[ ! -x "$sparkle/bin/generate_appcast" ]]; then
  mkdir -p "$sparkle"
  curl -sSfL "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz" | tar -xJ -C "$sparkle"
fi

build_number="$(git -C "$repo_root" rev-list --count HEAD)"
rm -rf "$out"
mkdir -p "$out"

step "Writing the release notes"
notes_dir="$out/notes"
"$repo_root/scripts/release-notes.sh" "$version" "$notes_dir" ${notes_args[@]+"${notes_args[@]}"}
if $review && [[ -t 0 ]]; then
  while true; do
    printf '\n%s\n\n' "$(cat "$notes_dir/release-notes.md")"
    read -r -p "Use these release notes? [Y]es, [e]dit, [q]uit: " answer
    case "$answer" in
      "" | y | Y) break ;;
      e | E)
        "${EDITOR:-vi}" "$notes_dir/notes.json"
        "$repo_root/scripts/release-notes.sh" "$version" "$notes_dir" --from "$notes_dir/notes.json" ;;
      q | Q) echo "stopped before building" >&2; exit 1 ;;
    esac
  done
fi

step "Archiving Keyline $version ($build_number)"
# The Release configuration signs manually with the Developer ID certificate and the "Keyline
# (Tunnel) Developer ID" profiles, which grant the -systemextension Network Extension values.
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
	<key>signingStyle</key><string>manual</string>
	<key>signingCertificate</key><string>Developer ID Application</string>
	<key>teamID</key><string>$team</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>ca.pulsbeat.keyline</key><string>Keyline Developer ID</string>
		<key>ca.pulsbeat.keyline.tunnel</key><string>Keyline Tunnel Developer ID</string>
	</dict>
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
# (Output captured first: with pipefail, grep -q closing the pipe early would fail codesign.)
for bundle in "$app" "$tunnel" "$app/Contents/Library/LoginItems/KeylineLoginHelper.app"; do
  details="$(codesign -dvv "$bundle" 2>&1)"
  [[ "$details" == *"Authority=$identity"* ]] \
    || { echo "error: $(basename "$bundle") is not signed with $identity" >&2; exit 1; }
done
for bundle in "$app" "$tunnel"; do
  entitlements="$(codesign -d --entitlements :- "$bundle" 2>/dev/null)"
  [[ "$entitlements" == *"packet-tunnel-provider-systemextension"* ]] \
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
# The key's Keychain item trusts only generate_keys, which created it, so generate_appcast reading
# it directly waits on a permission prompt. generate_keys exports it (it won't write to an
# existing path, so no pipe) to a private temporary file, removed as soon as signing is done.
key_dir="$(umask 077 && mktemp -d)"
# set -e applies in the trap too, so a missing key file (already removed) mustn't fail it.
trap 'rm -P "$key_dir"/key 2>/dev/null || true; rm -rf "$key_dir"' EXIT
(umask 077 && "$sparkle/bin/generate_keys" --account keyline -x "$key_dir/key" >/dev/null)
# Notes named after the DMG: the English ones are embedded, the Russian ones linked.
cp "$notes_dir"/Keyline-"$version"*.html "$dmg_dir"/
"$sparkle/bin/generate_appcast" --ed-key-file "$key_dir/key" \
  --download-url-prefix "$repo_url/releases/download/$tag/" \
  --release-notes-url-prefix "$repo_url/releases/download/$tag/" \
  --link "$repo_url" -o "$out/appcast.xml" "$dmg_dir"
rm -P "$key_dir/key"
grep -q 'sparkle:edSignature' "$out/appcast.xml" || { echo "error: appcast is not signed" >&2; exit 1; }

echo
echo "Release ready in $out:"
echo "  $(basename "$dmg")  (notarized, stapled)"
echo "  appcast.xml"
echo "  notes/release-notes.md, and the Sparkle notes next to the DMG"

if $publish; then
  step "Publishing $tag on GitHub"
  prerelease=()
  [[ "$tag" == *-* ]] && prerelease=(--prerelease)
  # The appcast links to the Russian notes in this release.
  assets=("$dmg" "$out/appcast.xml")
  [[ -f "$dmg_dir/Keyline-$version.ru.html" ]] && assets+=("$dmg_dir/Keyline-$version.ru.html")
  # Our notes first, then GitHub's list of merged pull requests.
  gh release create "$tag" ${prerelease[@]+"${prerelease[@]}"} --repo PrimeSeventyThree/keyline \
    --target "$(git -C "$repo_root" rev-parse HEAD)" --title "Keyline $version ($tag)" \
    --notes-file "$notes_dir/release-notes.md" --generate-notes "${assets[@]}"
fi
