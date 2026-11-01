#!/usr/bin/env bash
# Compares download speed through Keyline and the official Outline client: connects each
# VPN in turn with scutil, downloads the same file, and prints the exit IP and speed, so
# both runs share one server and one route. Speedtest picks its own test server per run,
# which makes screenshots from the two clients hard to compare.
#
# Usage: scripts/speed-ab.sh [rounds]   (default 3)
# The VPN names are the ones `scutil --nc list` shows; set KEYLINE_VPN and OUTLINE_VPN if
# yours differ. URL sets the file (speed.cloudflare.com doesn't download through the VPN).
set -u

rounds="${1:-3}"
keyline_vpn="${KEYLINE_VPN:-Outline Server 2}"
outline_vpn="${OUTLINE_VPN:-Outline Server}"
url="${URL:-https://proof.ovh.net/files/100Mb.dat}"

# Waits up to 30 s for a VPN to reach a state, printing it every second.
wait_state() { # vpn, state
  local i=0 s
  while [ $i -lt 30 ]; do
    s=$(scutil --nc status "$1" | head -1)
    printf '  %s: %s\n' "$1" "$s" >&2
    [ "$s" = "$2" ] && return 0
    sleep 1; i=$((i + 1))
  done
  return 1
}

run() { # label, vpn
  scutil --nc start "$2" && wait_state "$2" Connected || { echo "$1: failed to connect" >&2; return 1; }
  sleep 2
  local ip code size bps
  ip=$(curl -s --max-time 10 https://api.ipify.org)
  read -r code size bps <<< "$(curl -s -o /dev/null --max-time 120 -w '%{http_code} %{size_download} %{speed_download}' "$url")"
  printf '%s\t%s\tHTTP %s, %s bytes\t%.1f Mbps\n' "$1" "$ip" "$code" "$size" "$(printf '%s * 8 / 1000000\n' "$bps" | bc -l)"
  scutil --nc stop "$2"; wait_state "$2" Disconnected >/dev/null
}

r=1
while [ $r -le "$rounds" ]; do
  run keyline "$keyline_vpn"
  run outline "$outline_vpn"
  r=$((r + 1))
done
