#!/usr/bin/env bash
# Downloads DB-IP's free IP-to-Country Lite database (CC BY 4.0, https://db-ip.com) and
# converts its IPv4 ranges into Resources/GeoIP/ipv4-country.bin.
#
# Format: sorted records of 6 bytes, one per range: the range's first address as a
# big-endian UInt32, then the two-letter country code in ASCII ("ZZ" = unknown). A range
# ends where the next one starts. Gaps in the CSV are filled with "ZZ".
#
# Usage: scripts/update-geoip.sh [YYYY-MM]   (default: this month, falling back to last month)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="$repo_root/Resources/GeoIP"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

download() {
  curl -sSfL -o "$work/dbip.csv.gz" "https://download.db-ip.com/free/dbip-country-lite-$1.csv.gz"
}
if [[ $# -gt 0 ]]; then
  month="$1"
  download "$month"
else
  month="$(date +%Y-%m)"
  download "$month" 2>/dev/null || { month="$(date -v-1m +%Y-%m)"; download "$month"; }
fi

# IPv4 rows only, as hex records; fill gaps with ZZ and merge neighbours with the same country.
gunzip -c "$work/dbip.csv.gz" | LC_ALL=C awk -F, '
  function ip(s,  a) { split(s, a, "."); return ((a[1] * 256 + a[2]) * 256 + a[3]) * 256 + a[4] }
  function emit(start, cc) {
    if (cc == last) return
    printf "%08x%02x%02x\n", start, ord[substr(cc, 1, 1)], ord[substr(cc, 2, 1)]
    last = cc; records++
  }
  BEGIN { for (i = 65; i <= 90; i++) ord[sprintf("%c", i)] = i; next_start = 0; last = "" }
  $1 !~ /:/ {
    start = ip($1); end = ip($2); cc = $3
    if (cc !~ /^[A-Z][A-Z]$/) { print "bad country code: " $0 > "/dev/stderr"; exit 1 }
    if (start < next_start) { print "overlapping range: " $0 > "/dev/stderr"; exit 1 }
    if (start > next_start) emit(next_start, "ZZ")
    emit(start, cc)
    next_start = end + 1
  }
  END {
    if (next_start <= 4294967295) emit(next_start, "ZZ")
    print records " ranges" > "/dev/stderr"
  }' > "$work/records.hex"

mkdir -p "$out_dir"
xxd -r -p "$work/records.hex" > "$out_dir/ipv4-country.bin"
cat > "$out_dir/SOURCE.txt" <<EOF
ipv4-country.bin is derived from DB-IP IP to Country Lite, $month
(https://db-ip.com/db/download/ip-to-country-lite), licensed under the
Creative Commons Attribution 4.0 International License
(https://creativecommons.org/licenses/by/4.0/). Converted with scripts/update-geoip.sh.
EOF
echo "wrote $out_dir/ipv4-country.bin ($(wc -c < "$out_dir/ipv4-country.bin" | tr -d ' ') bytes) from $month"
