#!/usr/bin/env bash
# Finds the newest Outline macOS client release upstream and reports what changed since the
# commit third_party/outline-apps is pinned to. With --apply it also moves the submodule there
# and refreshes the licences; the weekly upstream-sync workflow then tests and opens a PR.
#
# Upstream tags macOS releases client_macos/vX.Y.Z, and since v1.19.5 only as release
# candidates (vX.Y.Z-rc.N), so those count too.
#
# The report covers:
#   - commits to the Go packages we bind (client/go/outline and below)
#   - upstream files changed behind our ported Swift files, found from their "Ported from"
#     headers, to port by hand
#   - go.mod changes, with a warning when Go moves past 1.25 (the last line supporting macOS 12)
#
# Usage: scripts/upstream-sync.sh [--tag <client_macos/vX.Y.Z>] [--report <file>] [--apply]
#   --tag      sync to this tag instead of the newest
#   --report   write the Markdown report there (default: print it)
#   --apply    check out the tag in the submodule and run scripts/update-licenses.sh
# In GitHub Actions it also writes up_to_date, tag, version and branch to $GITHUB_OUTPUT.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
sub="$repo_root/third_party/outline-apps"
upstream_url="https://github.com/OutlineFoundation/outline-apps"
max_go_minor=25

tag=""
report=""
apply=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) tag="$2"; shift 2 ;;
    --report) report="$2"; shift 2 ;;
    --apply) apply=true; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

log() { echo "[upstream-sync] $*" >&2; }
output() { [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "$1=$2" >> "$GITHUB_OUTPUT"; return 0; }

[[ -e "$sub/.git" ]] || { echo "error: submodule missing; run: git submodule update --init" >&2; exit 1; }

# "<tag> <commit>" for every client_macos tag; annotated tags resolve to their commit (^{}).
tags="$(git ls-remote --tags "$upstream_url.git" 'refs/tags/client_macos/*' | awk '
  { name = $2; sub(/^refs\/tags\//, "", name)
    if (name ~ /\^\{\}$/) { sub(/\^\{\}$/, "", name); peeled[name] = $1 } else plain[name] = $1 }
  END { for (n in plain) print n, (n in peeled ? peeled[n] : plain[n]) }')"

# Newest by version; a release sorts after its own release candidates.
if [[ -z "$tag" ]]; then
  tag="$(printf '%s\n' "$tags" | awk '{
      v = $1; sub(/^client_macos\/v/, "", v)
      rc = ""; if (split(v, parts, "-rc.") == 2) { v = parts[1]; rc = parts[2] }
      split(v, n, ".")
      printf "%05d%05d%05d%d%05d %s\n", n[1], n[2], n[3], (rc == "" ? 1 : 0), rc, $1 }' \
    | sort | tail -1 | cut -d' ' -f2)"
fi
new="$(printf '%s\n' "$tags" | awk -v t="$tag" '$1 == t { print $2 }')"
[[ -n "$new" ]] || { echo "error: no upstream tag $tag" >&2; exit 1; }
old="$(git -C "$sub" rev-parse HEAD)"
old_tag="$(printf '%s\n' "$tags" | awk -v s="$old" '$2 == s { print $1 }' | head -1)"
version="${tag#client_macos/}"
branch="upstream/${version}"
output tag "$tag"
output version "$version"
output branch "$branch"

if [[ "$new" == "$old" ]]; then
  log "already on $tag (${old:0:9})"
  output up_to_date true
  exit 0
fi
output up_to_date false
log "pinned ${old_tag:-${old:0:9}}, newest $tag (${new:0:9})"

# The log between the two needs history the submodule's shallow clone may not have.
[[ "$(git -C "$sub" rev-parse --is-shallow-repository)" == true ]] && git -C "$sub" fetch -q --unshallow origin
git -C "$sub" fetch -q origin "+refs/tags/$tag:refs/tags/$tag"
git -C "$sub" merge-base --is-ancestor "$old" "$new" \
  || log "note: $tag is on another release branch than the pinned commit; the lists show what $tag adds"

link() { echo "[\`${1:0:9}\`]($upstream_url/commit/$1)"; }
commits_in() { git -C "$sub" rev-list --count --no-merges "$old..$new" -- "$@"; }
go_directive() { git -C "$sub" show "$1:go.mod" | awk '$1 == "go" { print $2 }'; }

total="$(git -C "$sub" rev-list --count --no-merges "$old..$new")"
go_commits="$(commits_in client/go/outline)"
old_go="$(go_directive "$old")"
new_go="$(go_directive "$new")"

{
  echo "Moves \`third_party/outline-apps\` from ${old_tag:-\`${old:0:9}\`} to **$tag** ($total commits, [compare]($upstream_url/compare/$old...$new))."
  echo

  new_go_minor="$(echo "$new_go" | cut -d. -f2)"
  if [[ -n "$new_go_minor" && "$new_go_minor" -gt "$max_go_minor" ]]; then
    echo "> [!WARNING]"
    echo "> Upstream now needs Go $new_go. Go 1.$((max_go_minor + 1)) and later drop macOS 12, Keyline's minimum. core/build-xcframework.sh pins Go 1.$max_go_minor; decide whether to raise the minimum macOS before merging."
    echo
  fi

  echo "## Go core ($go_commits commits to \`client/go/outline\`)"
  echo
  if [[ "$go_commits" == 0 ]]; then
    echo "No changes to the Go packages Keyline binds."
  else
    git -C "$sub" log --no-merges --format='%H %s' "$old..$new" -- client/go/outline | head -40 \
      | while read -r sha subject; do echo "- $(link "$sha") $subject"; done
    [[ "$go_commits" -gt 40 ]] && echo "- …and $((go_commits - 40)) more"
  fi
  echo

  echo "## To port by hand"
  echo
  echo "Upstream sources of Keyline's ported Swift files (from their \"Ported from\" headers) that changed:"
  echo
  any=false
  while IFS= read -r file; do
    paths="$(head -8 "$repo_root/$file" | grep -oE 'client/[A-Za-z0-9_./-]+' | sed -E 's/[.,)]+$//' | sort -u || true)"
    [[ -n "$paths" ]] || continue
    while IFS= read -r path; do
      count="$(commits_in "$path")"
      [[ "$count" == 0 ]] && continue
      any=true
      echo "- [ ] \`$file\` ← [\`$path\`]($upstream_url/tree/$new/$path): $count commits"
      git -C "$sub" log --no-merges --format='%H %s' "$old..$new" -- "$path" | head -5 \
        | while read -r sha subject; do echo "  - $(link "$sha") $subject"; done
    done <<< "$paths"
  done < <(cd "$repo_root" && grep -rl "Ported from" App Shared TunnelExtension Tests 2>/dev/null | sort)
  $any || echo "None: the ported sources didn't change."
  echo

  echo "## Go and dependencies"
  echo
  if [[ "$old_go" == "$new_go" ]]; then echo "Go directive unchanged: \`go $new_go\`."; else echo "Go directive: \`go $old_go\` → \`go $new_go\`."; fi
  if git -C "$sub" diff --quiet "$old" "$new" -- go.mod go.sum; then
    echo "go.mod and go.sum unchanged."
  else
    echo
    echo "<details><summary>go.mod diff</summary>"
    echo
    echo '```diff'
    git -C "$sub" diff "$old" "$new" -- go.mod | head -150
    echo '```'
    echo
    echo "</details>"
  fi
} > "${report:-/dev/stdout}"

if $apply; then
  log "checking out $tag"
  git -C "$sub" checkout -q "$new"
  "$repo_root/scripts/update-licenses.sh" >&2
fi
