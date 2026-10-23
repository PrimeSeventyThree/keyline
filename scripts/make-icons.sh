#!/usr/bin/env bash
# Builds Keyline's icons from the SVG masters in design/logo:
# - App/Assets.xcassets/AppIcon.appiconset: every macOS app icon size, from keyline-icon.svg
# - App/Assets.xcassets/KeylineMark.imageset: the one-colour mark as a vector template image,
#   from keyline-mark.svg (menu bar and in-app use)
#
# Usage: scripts/make-icons.sh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
logo="$repo_root/design/logo"
catalog="$repo_root/App/Assets.xcassets"

icon_set="$catalog/AppIcon.appiconset"
rm -rf "$icon_set" && mkdir -p "$icon_set"
entries=()
for points in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((points * scale))
    name="icon_${points}x${points}@${scale}x.png"
    "$repo_root/scripts/render-svg.sh" "$logo/keyline-icon.svg" "$pixels" "$icon_set/$name"
    entries+=("    { \"filename\" : \"$name\", \"idiom\" : \"mac\", \"scale\" : \"${scale}x\", \"size\" : \"${points}x${points}\" }")
  done
done
cat > "$icon_set/Contents.json" <<EOF
{
  "images" : [
$(printf '%s,\n' "${entries[@]}" | sed '$ s/,$//')
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

mark_set="$catalog/KeylineMark.imageset"
rm -rf "$mark_set" && mkdir -p "$mark_set"
cp "$logo/keyline-mark.svg" "$mark_set/keyline-mark.svg"
cat > "$mark_set/Contents.json" <<EOF
{
  "images" : [ { "filename" : "keyline-mark.svg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
EOF
echo "app icon: $(ls "$icon_set" | grep -c png) sizes; mark: $mark_set"
