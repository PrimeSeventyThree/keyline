# Shared OpenRouter helpers for the release scripts (sourced, not run).
#
# Every paid call goes through openrouter_post, which first checks a budget
# guard against the key's live usage and a per-run call limit, then records the
# call's cost in a ledger. When the guard says no, callers fall back to their
# no-AI path, so a release never fails over budget.
#
# Guards, in USD; override with environment variables:
#   OPENROUTER_MONTHLY_CAP    stop when the key's spend this month reaches it (default 1.00)
#   OPENROUTER_DAILY_CAP      stop when the key's spend today reaches it (default 0.20)
#   OPENROUTER_MIN_REMAINING  stop when the key's own limit has less left (default 0.10)
#   OPENROUTER_MAX_CALLS      paid calls allowed per script run (default 60)
# The key's own credit limit, set in OpenRouter, is the hard cap behind these.
#
# Callers define log() before sourcing; these helpers log to stderr so their
# messages survive being called inside $(...).

OPENROUTER_API="https://openrouter.ai/api"
# The Jev router's key, unless OPENROUTER_KEY is set.
: "${OPENROUTER_KEY:=$(cat "$HOME/.config/jev/openrouter_key" 2>/dev/null)}"
: "${OPENROUTER_MONTHLY_CAP:=1.00}"
: "${OPENROUTER_DAILY_CAP:=0.20}"
: "${OPENROUTER_MIN_REMAINING:=0.10}"
: "${OPENROUTER_MAX_CALLS:=60}"

# One line per paid call: "<cost>". A file, because calls often run in $(...)
# subshells where shell variables would not survive.
OPENROUTER_LEDGER=$(mktemp)
OPENROUTER_GUARD=$(mktemp)

# Checks the key once per run (cached); returns 0 when spending is allowed
openrouter_budget_ok() {
    if [ -s "$OPENROUTER_GUARD" ]; then
        [ "$(cat "$OPENROUTER_GUARD")" = ok ]
        return
    fi
    if [ -z "${OPENROUTER_KEY:-}" ]; then
        verdict="OPENROUTER_KEY not set"
    elif ! key=$(curl -sf --max-time 10 "$OPENROUTER_API/v1/key" -H "Authorization: Bearer $OPENROUTER_KEY"); then
        verdict="could not read the key's usage"
    else
        verdict=$(printf '%s\n' "$key" | jq -r \
            --argjson month "$OPENROUTER_MONTHLY_CAP" --argjson day "$OPENROUTER_DAILY_CAP" --argjson left "$OPENROUTER_MIN_REMAINING" '
            .data as $k
            | if ($k.usage_monthly // 0) >= $month then "spend this month $\($k.usage_monthly) reached the $\($month) cap"
              elif ($k.usage_daily // 0) >= $day then "spend today $\($k.usage_daily) reached the $\($day) cap"
              elif $k.limit != null and ($k.limit_remaining // 0) < $left then "key limit nearly used up ($\($k.limit_remaining) left)"
              else "ok" end' 2>/dev/null)
        [ -n "$verdict" ] || verdict="unexpected key status response"
        if [ "$verdict" = ok ]; then
            printf '%s\n' "$key" | jq -r '.data | "OpenRouter key: spent today $\(.usage_daily // 0), this month $\(.usage_monthly // 0), limit \(if .limit == null then "NONE - set one in OpenRouter" else "$\(.limit) (\(.limit_remaining) left)" end)"' \
                | while read -r line; do log "$line" >&2; done
        fi
    fi
    printf '%s\n' "$verdict" > "$OPENROUTER_GUARD"
    [ "$verdict" = ok ] || log "AI calls skipped: $verdict" >&2
    [ "$verdict" = ok ]
}

# POSTs a JSON body to an OpenRouter endpoint and prints the response;
# returns 1 without calling when the guard or the call limit says no
openrouter_post() {
    endpoint=$1 body=$2
    openrouter_budget_ok || return 1
    if [ "$(wc -l < "$OPENROUTER_LEDGER")" -ge "$OPENROUTER_MAX_CALLS" ]; then
        log "AI call limit ($OPENROUTER_MAX_CALLS per run) reached" >&2
        printf "%s\n" "call limit reached" > "$OPENROUTER_GUARD"
        return 1
    fi
    response=$(curl -sf --max-time 30 "$OPENROUTER_API/$endpoint" \
        -H "Authorization: Bearer $OPENROUTER_KEY" -H "Content-Type: application/json" -d "$body") || return 1
    printf '%s\n' "$response" | jq -r '.usage.cost // 0' >> "$OPENROUTER_LEDGER"
    printf '%s\n' "$response"
}

# Prints "<calls> calls, $<total>" for this run
openrouter_spent() {
    awk '{ n++; s += $1 } END { printf "%d calls, $%.6f\n", n, s }' "$OPENROUTER_LEDGER"
}
