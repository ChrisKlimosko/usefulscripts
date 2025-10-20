#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
FALLBACK_SERVERS=(whois.arin.net whois.ripe.net whois.apnic.net whois.lacnic.net whois.afrinic.net)
CONNECT_TIMEOUT=8        # seconds for each whois call
SLEEP_BETWEEN=0          # bump to 0.2–0.5 if you hit rate limits

# --- Helpers ---
err() { printf '%s\n' "$*" >&2; }

trim() {
  # trims leading/trailing whitespace + CR
  printf '%s' "$1" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

normalize_target() {
  # Strip optional CIDR (e.g., 2001:db8::1/64 -> 2001:db8::1 ; 1.2.3.4/24 -> 1.2.3.4)
  printf '%s' "$1" | sed 's#/.*$##'
}

is_ipv4_like() { [[ "$1" == *.* ]]; }
is_ipv6_like() { [[ "$1" == *:* ]]; }

run_whois() {
  # $1: server (may be empty to use default client behavior)
  # $2: target (IP)
  local server="$1" target="$2" out rc
  if [[ -n "$server" ]]; then
    out=$(timeout "$CONNECT_TIMEOUT" whois -h "$server" "$target" < /dev/null 2>&1) || rc=$?
  else
    out=$(timeout "$CONNECT_TIMEOUT" whois "$target" < /dev/null 2>&1) || rc=$?
  fi
  rc="${rc:-0}"
  printf '%s' "$out"
  return "$rc"
}

extract_referral_host() {
  # Parse ReferralServer or whois:// from ARIN-style responses
  # Example line: "ReferralServer: whois://whois.apnic.net"
  awk -F'whois://' 'BEGIN{IGNORECASE=1} /ReferralServer:[[:space:]]*whois:\/\//{print $2; exit}' \
  | awk '{print $1}' \
  | sed 's#/.*$##'
}

extract_iana_refer() {
  # Pull "refer:" or "whois:" from whois.iana.org response
  awk -F':[[:space:]]*' 'BEGIN{IGNORECASE=1} $1 ~ /^(refer|whois)$/ {print $2; exit}'
}

get_best_server_for_ip() {
  # Ask IANA whois which RIR handles this address
  # If that fails, we'll try fallbacks.
  local ip="$1" iana srv
  iana=$(run_whois "whois.iana.org" "$ip" || true)
  srv=$(printf '%s\n' "$iana" | extract_iana_refer || true)
  if [[ -n "$srv" ]]; then
    printf '%s' "$srv"
    return 0
  fi
  # No IANA referral—fall back by ip "shape".
  if is_ipv4_like "$ip" || is_ipv6_like "$ip"; then
    printf '%s' "${FALLBACK_SERVERS[0]}"
  else
    printf '%s' ""
  fi
}

# --- Usage / args ---
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <input_file>"
  exit 1
fi

input_file=$1
if [[ ! -f "$input_file" ]]; then
  err "Input file '$input_file' not found."
  exit 1
fi

# DO NOT redirect output to the same file as input; that will truncate it.
# Wrong:  ./whois_bulk.sh ips.txt > ips.txt
# Right:  ./whois_bulk.sh ips.txt > whois_output.txt

while IFS= read -r raw || [[ -n "$raw" ]]; do
  line=$(trim "$raw")
  [[ -z "$line" ]] && continue
  [[ "$line" == \#* ]] && continue

  target=$(normalize_target "$line")

  # Quick sanity: v4/v6-ish
  if ! (is_ipv4_like "$target" || is_ipv6_like "$target"); then
    err "Skipping non-IP input: '$line'"
    echo "-----------------------------------"
    continue
  fi

  # Determine primary server via IANA
  primary_srv=$(get_best_server_for_ip "$target")
  [[ -z "$primary_srv" ]] && primary_srv=""  # allow client default if truly unknown

  echo "WHOIS lookup for: $target"
  [[ -n "$primary_srv" ]] && echo "(server: $primary_srv)"

  first=$(run_whois "$primary_srv" "$target" || true)
  printf '%s\n' "$first"

  # Follow one referral hop if present (common with ARIN → {APNIC,RIPE,...})
  referral=$(printf '%s\n' "$first" | extract_referral_host || true)
  if [[ -n "$referral" && "$referral" != "$primary_srv" ]]; then
    echo
    echo "---- Following referral -> $referral ----"
    second=$(run_whois "$referral" "$target" || true)
    printf '%s\n' "$second"
  fi

  echo "-----------------------------------"
  [[ "$SLEEP_BETWEEN" != "0" ]] && sleep "$SLEEP_BETWEEN"
done < "$input_file"
