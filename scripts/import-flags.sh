#!/usr/bin/env bash
# Imports the square (1x1) country flags from flag-icons (MIT, https://github.com/lipis/flag-icons)
# into App/Assets.xcassets/Flags as vector SVG image sets named by lowercase ISO 3166-1 code,
# e.g. "Flags/ca". Replaces any flags imported before.
#
# Usage: scripts/import-flags.sh [version]   (default below)
set -euo pipefail

version="${1:-7.6.0}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
catalog="$repo_root/App/Assets.xcassets"
flags_dir="$catalog/Flags"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -sSfL -o "$work/flag-icons.tgz" "https://registry.npmjs.org/flag-icons/-/flag-icons-$version.tgz"
mkdir "$work/pkg"
tar -xzf "$work/flag-icons.tgz" -C "$work/pkg" package/flags/1x1 package/LICENSE

mkdir -p "$catalog"
[[ -f "$catalog/Contents.json" ]] || printf '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' > "$catalog/Contents.json"
rm -rf "$flags_dir"
mkdir -p "$flags_dir"
printf '{\n  "info" : { "author" : "xcode", "version" : 1 },\n  "properties" : { "provides-namespace" : true }\n}\n' > "$flags_dir/Contents.json"

command -v rsvg-convert >/dev/null || { echo "error: rsvg-convert missing; run: brew install librsvg" >&2; exit 1; }

# Xcode's SVG renderer skips <use> references and mishandles some clip paths (bi, pw), which
# leaves those flags blank or incomplete. librsvg rewrites such files as plain-path SVGs.
needs_flattening() {
  grep -q '<use' "$1" || [[ "$(basename "$1")" == bi.svg || "$(basename "$1")" == pw.svg ]]
}

count=0
flattened=0
for svg in "$work"/pkg/package/flags/1x1/*.svg; do
  code="$(basename "$svg" .svg)"
  set_dir="$flags_dir/$code.imageset"
  mkdir "$set_dir"
  if needs_flattening "$svg"; then
    # librsvg writes colours as rgb(r%, g%, b%); Xcode misreads percentages below 1 (navy
    # turns purple), so convert them to #rrggbb.
    rsvg-convert -f svg "$svg" | perl -pe '
      s{rgb\(\s*([\d.]+)%,\s*([\d.]+)%,\s*([\d.]+)%\s*\)}{sprintf("#%02x%02x%02x", map { int($_ * 2.55 + 0.5) } $1, $2, $3)}ge
    ' > "$set_dir/$code.svg"
    flattened=$((flattened + 1))
  else
    cp "$svg" "$set_dir/$code.svg"
  fi
  cat > "$set_dir/Contents.json" <<EOF
{
  "images" : [ { "filename" : "$code.svg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true }
}
EOF
  count=$((count + 1))
done

mkdir -p "$repo_root/Resources/Licenses"
cp "$work/pkg/package/LICENSE" "$repo_root/Resources/Licenses/flag-icons.txt"
echo "imported $count flags from flag-icons $version ($flattened flattened with librsvg)"
