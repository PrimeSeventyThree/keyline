#!/usr/bin/env bash
# Writes Keyline's "What's new" release notes, in English and Russian, from the commits since
# the previous release tag:
#
#   1. drop housekeeping commits (only scripts, CI, project files, tests, docs, design)
#   2. Jev, per commit: would a user notice it? new / fixed / improved
#   3. Claude Haiku (via OpenRouter) words the kept commits for users, in English and Russian
#   4. the script renders a fixed format with at most 8 items
# Without AI (budget guard, no key, bad reply) the kept commit subjects are listed as they are,
# in English only. Paid calls go through openrouter.sh's budget guard.
#
# Writes, into <out-dir>:
#   Keyline-<version>.html     English notes, embedded in the Sparkle appcast
#   Keyline-<version>.ru.html  Russian notes; the appcast links to it (uploaded with the release)
#   release-notes.md           both languages, for the GitHub release
#   notes.json                 the notes as data, to edit and render again with --from
#
# Usage: scripts/release-notes.sh <version> <out-dir> [--since <ref>]
#        scripts/release-notes.sh <version> <out-dir> --from <notes.json>
#        scripts/release-notes.sh --preview [--since <ref>]   prints the notes for HEAD only
#   --since   the commit or tag to start from (default: the latest v* tag before HEAD)
#   --from    render notes.json (written on every run, for editing) instead of asking the AI
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
haiku_model="anthropic/claude-haiku-5.5"
max_items=8
max_commits=40
jev_visible_min="0.50"
app_description="Keyline, a macOS VPN client for Outline access keys (ss:// and ssconf://), with a main window and a menu bar item"
# Commits touching only these paths are housekeeping users never see.
housekeeping='^(scripts/|core/|\.github/|Keyline\.xcodeproj/|project\.yml$|Tests/|docs/|design/|Resources/Licenses/|\.git(ignore|modules|attributes)$|.*\.md$)'

log() { echo "[release-notes] $*" >&2; }

preview=false
from=""
since=""
version=""
out_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview) preview=true; shift ;;
    --since) since="$2"; shift 2 ;;
    --from) from="$2"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) if [[ -z "$version" ]]; then version="$1"; else out_dir="$1"; fi; shift ;;
  esac
done
if $preview; then
  version="${version:-$(sed -n 's/.*MARKETING_VERSION = \([0-9.]*\);/\1/p' "$repo_root/Keyline.xcodeproj/project.pbxproj" | sort -uV | tail -1)}"
  out_dir="$(mktemp -d)"
elif [[ -z "$version" || -z "$out_dir" ]]; then
  echo "usage: scripts/release-notes.sh <version> <out-dir> [--since <ref> | --from <notes.json>] | --preview [--since <ref>]" >&2
  exit 2
fi
mkdir -p "$out_dir"

. "$repo_root/scripts/openrouter.sh"

if [[ -n "$from" ]]; then
  # Edited notes: render them as they are.
  notes="$(jq -c '{en, ru} | with_entries(select(.value != null))' "$from")" || { echo "error: $from is not valid JSON" >&2; exit 1; }
else
  # ---------- 1. commits since the previous release ----------

  first_release=false
  if [[ -z "$since" ]]; then
    since="$(git -C "$repo_root" describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null || true)"
  fi
  if [[ -n "$since" ]]; then
    log "changes since $since"
    shas="$(git -C "$repo_root" rev-list --no-merges "$since..HEAD")"
  else
    log "no earlier release tag: this is the first release"
    first_release=true
    shas="$(git -C "$repo_root" rev-list --no-merges HEAD)"
  fi
  total="$(printf '%s\n' "$shas" | grep -c . || true)"

  kept="$(mktemp)"
  for sha in $(printf '%s\n' "$shas" | head -"$max_commits"); do
    subject="$(git -C "$repo_root" log -1 --format=%s "$sha")"
    files="$(git -C "$repo_root" diff-tree --no-commit-id --name-only -r "$sha")"
    [[ -z "$(printf '%s\n' "$files" | grep -vE "$housekeeping")" ]] && continue
    printf '%s\t%s\n' "$sha" "$subject" >> "$kept"
  done
  log "$total commits, $(wc -l < "$kept" | tr -d ' ') beyond housekeeping"

  # ---------- 2. Jev: visible to users? which kind? ----------

  sorted="$(mktemp)" # "<kind>\t<subject>\t<sha>", kind is new/fixed/improved, or changes without Jev
  while IFS=$'\t' read -r sha subject; do
    kind=changes
    if openrouter_budget_ok; then
      files="$(git -C "$repo_root" diff-tree --no-commit-id --name-only -r "$sha" | head -15 | jq -R . | jq -s .)"
      body="$(jq -n --arg subject "$subject" --argjson files "$files" --arg app "$app_description" '{
        model: "~typesafe/jev-latest",
        state: { app: $app, commit_subject: $subject, changed_files: $files },
        questions: {
          visible: { type: "noul", instructions: "Someone using the app would notice this change: new behaviour, a fix they could hit, or a visible improvement" },
          kind: { type: "choice", instructions: "What kind of change is this for a user?", criteria: {
            new: "A new feature or capability",
            fixed: "A bug, crash or wrong behaviour that is now fixed",
            improved: "Something existing that works or looks better, or is faster"
          } }
        }
      }')"
      answer="$(openrouter_post alpha/decisions "$body" | jq -r '"\(.answers.visible.noul) \(.answers.kind.choice)"' 2>/dev/null)"
      if [[ -n "$answer" && "${answer% *}" != null ]]; then
        awk -v v="${answer% *}" -v m="$jev_visible_min" 'BEGIN { exit !(v >= m) }' || continue
        kind="${answer#* }"
      fi
    fi
    printf '%s\t%s\t%s\n' "$kind" "$subject" "$sha" >> "$sorted"
  done < "$kept"

  # {new, fixed, improved, changes}: lists of commit subjects
  grouped="$(jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | {kind: .[0], subject: .[1]})
    | reduce .[] as $c ({}; .[$c.kind] += [$c.subject])' "$sorted")"

  # The same with each commit's first body paragraph, which often says what users ran into, for Haiku.
  detailed="$(while IFS=$'\t' read -r kind subject sha; do
    detail="$(git -C "$repo_root" log -1 --format=%b "$sha" | awk 'NF { printf "%s ", $0; next } seen { exit } { seen = 1 }' | cut -c1-300)"
    jq -n --arg kind "$kind" --arg subject "$subject" --arg detail "$detail" '{kind: $kind, subject: $subject, detail: $detail}'
  done < "$sorted" | jq -s -c 'reduce .[] as $c ({}; .[$c.kind] += [{subject: $c.subject, detail: $c.detail}])')"

  # ---------- 3. Haiku: user-facing wording, English and Russian ----------

  notes="" # {"en": {new, fixed, improved}, "ru": {...}}
  if [[ -s "$sorted" ]] && openrouter_budget_ok; then
    first_note=""
    $first_release && first_note=' This is the first release: describe what the app does and offers as "new" items, not individual changes.'
    system='You write short "What'"'"'s new" release notes for '"$app_description"'. You get commits grouped as new, fixed, improved and changes (changes = not yet sorted), each with its subject and the start of its description, which often says what users ran into. Rewrite them in plain, friendly language for people using the app: say what they will see or can now do, not how the code changed. Merge related commits and leave out anything a user cannot notice. Never invent features, numbers or details that are not in the input. Use at most '"$max_items"' items in total, each one short sentence under 120 characters.'"$first_note"' Write the same notes in English and in natural Russian (use «» quotes, and the app'"'"'s Russian UI terms: «Настройки», «Серверы», «Подключить»). Reply with JSON only, no other text: {"en": {"new": [...], "fixed": [...], "improved": [...]}, "ru": {"new": [...], "fixed": [...], "improved": [...]}}'
    body="$(jq -n --arg model "$haiku_model" --arg system "$system" --arg input "$detailed" '{
      model: $model, max_tokens: 3000, reasoning: { effort: "low" }, usage: { include: true },
      messages: [ { role: "system", content: $system }, { role: "user", content: $input } ]
    }')"
    reply="$(openrouter_post v1/chat/completions "$body" | jq -r '.choices[0].message.content // empty' 2>/dev/null \
      | sed -e 's/^```json//' -e 's/^```//')"
    [[ -n "${KEYLINE_NOTES_DEBUG:-}" ]] && printf '%s\n' "$reply" > "$KEYLINE_NOTES_DEBUG"
    if printf '%s\n' "$reply" | jq -e --argjson max "$max_items" '
        def lines: (. // []) | type == "array" and all(.[]; type == "string" and length > 0 and length <= 160);
        def count: ((.new // []) + (.fixed // []) + (.improved // [])) | length;
        # Not "... and (...) as $n | ...": that binds the whole "and" chain to $n.
        def valid: (.new | lines) and (.fixed | lines) and (.improved | lines) and count >= 1 and count <= $max;
        (.en | valid) and (.ru | valid)' >/dev/null 2>&1; then
      notes="$(printf '%s\n' "$reply" | jq -c '{en: (.en | {new, fixed, improved}), ru: (.ru | {new, fixed, improved})}')"
      log "notes written by $haiku_model"
    else
      log "Haiku reply missing or invalid, listing commit subjects. Reply: $(printf '%s' "$reply" | tr '\n' ' ' | cut -c1-400)"
    fi
  fi

  # ---------- 4. fallback: the commit subjects as they are, in English ----------

  if [[ -z "$notes" ]]; then
    if [[ -s "$sorted" ]]; then
      notes="$(printf '%s\n' "$grouped" | jq -c --argjson max "$max_items" '
        with_entries(.value |= map(sub("\\.$"; ""))) as $g
        | [("new", "fixed", "improved", "changes") as $k | ($g[$k] // [])[] | {k: $k, s: .}] as $all
        | ($all[:$max] | reduce .[] as $i ({}; .[$i.k] += [$i.s]))
        | if ($all | length) > $max then .changes += ["…and \(($all | length) - $max) more changes"] else . end
        | {en: .}')"
    else
      notes='{"en": {"improved": ["Behind-the-scenes maintenance, with no visible changes."]}, "ru": {"improved": ["Внутренние улучшения без видимых изменений."]}}'
    fi
  fi
fi

# ---------- render ----------

# Kept for editing: scripts/release-notes.sh <version> <out-dir> --from <out-dir>/notes.json
printf '%s\n' "$notes" | jq . > "$out_dir/notes.json"

# The notes for language $1 as an HTML fragment, empty when there are none in that language.
render_html() {
  printf '%s\n' "$notes" | jq -r --arg lang "$1" '
    (if $lang == "ru" then {new: "Новое", fixed: "Исправлено", improved: "Улучшено", changes: "Изменения"}
     else {new: "New", fixed: "Fixed", improved: "Improved", changes: "Changes"} end) as $titles
    | (.[$lang] // {}) as $n
    | [("new", "fixed", "improved", "changes") as $k | select(($n[$k] // []) | length > 0)
       | "<h3>\($titles[$k])</h3>\n<ul>\n" + ($n[$k] | map("<li>\(@html "\(.)")</li>") | join("\n")) + "\n</ul>"]
    | join("\n")'
}

# The notes for language $1 as Markdown, under level-3 headings.
render_markdown() {
  printf '%s\n' "$notes" | jq -r --arg lang "$1" '
    (if $lang == "ru" then {new: "Новое", fixed: "Исправлено", improved: "Улучшено", changes: "Изменения"}
     else {new: "New", fixed: "Fixed", improved: "Improved", changes: "Changes"} end) as $titles
    | (.[$lang] // {}) as $n
    | [("new", "fixed", "improved", "changes") as $k | select(($n[$k] // []) | length > 0)
       | "### \($titles[$k])\n\n" + ($n[$k] | map("- \(.)") | join("\n"))]
    | join("\n\n")'
}

en_html="$(render_html en)"
ru_html="$(render_html ru)"
# A fragment, so generate_appcast embeds it in the appcast.
printf '%s\n' "$en_html" > "$out_dir/Keyline-$version.html"
# Sparkle opens linked notes as a page, so this one is a whole document with its charset.
if [[ -n "$ru_html" ]]; then
  cat > "$out_dir/Keyline-$version.ru.html" <<EOF
<!DOCTYPE html>
<html lang="ru"><head><meta charset="utf-8"><title>Keyline $version</title>
<style>body { font: 13px -apple-system, sans-serif; margin: 12px 16px; } h3 { font-size: 13px; margin: 12px 0 4px; } ul { margin: 0; padding-left: 20px; }
@media (prefers-color-scheme: dark) { body { color: #e6e6e6; background: transparent; } }</style>
</head><body>
$ru_html
</body></html>
EOF
else
  rm -f "$out_dir/Keyline-$version.ru.html"
fi
{
  render_markdown en
  if [[ -n "$ru_html" ]]; then
    printf '\n\n<details><summary>На русском</summary>\n\n%s\n\n</details>\n' "$(render_markdown ru)"
  fi
} > "$out_dir/release-notes.md"

log "wrote $out_dir: Keyline-$version.html${ru_html:+, Keyline-$version.ru.html}, release-notes.md, notes.json"
[[ -s "$OPENROUTER_LEDGER" ]] && log "AI usage: $(openrouter_spent)"
if $preview; then
  cat "$out_dir/release-notes.md"
  rm -rf "$out_dir"
fi
exit 0
