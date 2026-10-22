#!/usr/bin/env bash
# Renders an SVG to PNG with librsvg, after resolving CSS custom properties.
#
# Keyline's brand SVGs keep their colours as CSS variables (one palette block to edit), but
# librsvg doesn't support var(), so this replaces each var(--name) with the value declared
# as "--name: value;" in the file before rendering.
#
# Usage: scripts/render-svg.sh input.svg size output.png
set -euo pipefail

[[ $# -eq 3 ]] || { echo "usage: $0 input.svg size output.png" >&2; exit 2; }
command -v rsvg-convert >/dev/null || { echo "error: rsvg-convert missing; run: brew install librsvg" >&2; exit 1; }

perl -0pe '
  my %vars;
  $vars{$1} = $2 while /--([\w-]+)\s*:\s*([^;]+?)\s*;/g;
  s/var\(--([\w-]+)\)/exists $vars{$1} ? $vars{$1} : die "undefined variable --$1\n"/ge;
' "$1" | rsvg-convert -w "$2" -h "$2" -o "$3"
