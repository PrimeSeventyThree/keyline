#!/usr/bin/env bash
# Updates Resources/Localizable.xcstrings from the code and fills in the Russian text from
# Localization/ru.json (key → translation). Run after adding or changing user-facing text,
# then translate any keys it lists as missing.
#
# Usage: scripts/update-strings.sh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
catalog="$repo_root/Resources/Localizable.xcstrings"
translations="$repo_root/Localization/ru.json"
derived_data="${KEYLINE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Keyline-strings}"

[[ -d "$repo_root/build/core/Tun2socks.xcframework" ]] || "$repo_root/core/build-xcframework.sh"
[[ -f "$catalog" ]] || printf '{\n  "sourceLanguage" : "en",\n  "strings" : {},\n  "version" : "1.0"\n}\n' > "$catalog"

# The compiler writes every String(localized:) and SwiftUI text key to .stringsdata files.
xcodebuild build \
  -project "$repo_root/Keyline.xcodeproj" -scheme Keyline -configuration Debug \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO SWIFT_EMIT_LOC_STRINGS=YES \
  | grep -E 'error:|BUILD FAILED' || true

args=()
while IFS= read -r file; do
  args+=(--stringsdata "$file")
done < <(find "$derived_data/Build/Intermediates.noindex" -name '*.stringsdata' -path '*/Keyline.build/*')
[[ ${#args[@]} -gt 0 ]] || { echo "error: no .stringsdata found; did the build fail?" >&2; exit 1; }
xcrun xcstringstool sync "$catalog" "${args[@]}"

# Russian from Localization/ru.json. English is marked translated so the build emits en.lproj;
# without it macOS would see Russian as the app's only language.
jq --slurpfile ru "$translations" '
  .strings |= with_entries(
    if .value.localizations.en.stringUnit then .value.localizations.en.stringUnit.state = "translated" else . end)
  | .strings |= with_entries(
    if $ru[0][.key] != null
    then .value.localizations.ru = { "stringUnit": { "state": "translated", "value": $ru[0][.key] } }
    else . end)
' "$catalog" > "$catalog.new" && mv "$catalog.new" "$catalog"

# Keys with words in them (not just format specifiers or symbols) but no Russian yet.
missing="$(jq -r --slurpfile ru "$translations" '
  .strings | to_entries[]
  | select(.value.extractionState != "stale")
  | select(.key | gsub("%([0-9]+\\$)?(@|lld|ld|d|f)"; "") | test("[A-Za-z]"))
  | select($ru[0][.key] == null) | .key
' "$catalog")"
total="$(jq '.strings | length' "$catalog")"
if [[ -n "$missing" ]]; then
  echo "$total strings; missing Russian for:"
  echo "$missing" | sed 's/^/  /'
  exit 1
fi
echo "$total strings, all translated"
