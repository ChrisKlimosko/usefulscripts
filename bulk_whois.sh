#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# bulkwhois.sh — polite bulk WHOIS for domains and IPs
#
# Usage:
#   ./bulkwhois.sh <input_file> [> results.txt]
#   ./bulkwhois.sh -            # read targets from stdin
#
# One target per line. Blank lines and lines starting with # are ignored.
# Progress/warnings go to stderr; WHOIS results go to stdout (or OUTPUT_FILE).
#
# Tunables (override via environment, e.g. `SLEEP_BETWEEN=3 ./bulkwhois.sh x`):
#   CONNECT_TIMEOUT      seconds per whois call                (default 25)
#   MAX_RETRIES          retries on timeout/rate-limit         (default 3)
#   BASE_BACKOFF         backoff seconds, grows per attempt    (default 4)
#   SLEEP_BETWEEN        polite pause between targets          (default 2)
#   MIN_SERVER_INTERVAL  min seconds between hits to a server  (default 3)
#   MAX_REFERRALS        referral hops to follow               (default 2)
#   OUTPUT_FILE          write results here instead of stdout  (default "")
# =============================================================================

CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-25}"
MAX_RETRIES="${MAX_RETRIES:-3}"
BASE_BACKOFF="${BASE_BACKOFF:-4}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-2}"
MIN_SERVER_INTERVAL="${MIN_SERVER_INTERVAL:-3}"
MAX_REFERRALS="${MAX_REFERRALS:-2}"
OUTPUT_FILE="${OUTPUT_FILE:-}"

FALLBACK_SERVERS=(whois.arin.net whois.ripe.net whois.apnic.net whois.lacnic.net whois.afrinic.net)

# Per-server "last hit" timestamps, for rate limiting.
declare -A LAST_HIT

# --- Logging (always to stderr so it never pollutes results) ---
log()  { printf '%s\n' "$*" >&2; }
err()  { printf 'ERROR: %s\n' "$*" >&2; }

# --- Clean exit on Ctrl-C / kill, instead of a stack of ugly messages ---
cleanup() { log ""; log "Interrupted — stopping."; exit 130; }
trap cleanup INT TERM

# --- Preflight checks ---
command -v whois   >/dev/null 2>&1 || { err "'whois' is not installed (try: apt install whois)."; exit 1; }
command -v timeout >/dev/null 2>&1 || { err "'timeout' is not installed (part of coreutils)."; exit 1; }

# --- Small helpers ---
trim() { printf '%s' "$1" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

normalize_target() {
  # Strip scheme, userinfo, path/CIDR, query and trailing dot. Lowercase.
  # Leaves IPv6 colons intact.
  local t="$1"
  t="$(printf '%s' "$t" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##')"  # scheme://
  t="${t##*@}"        # user:pass@
  t="${t%%/*}"        # /path or /CIDR
  t="${t%%\?*}"       # ?query
  # Bracketed IPv6 with optional port: [2001:db8::1]:443 -> 2001:db8::1
  if [[ "$t" =~ ^\[(.+)\](:[0-9]+)?$ ]]; then
    t="${BASH_REMATCH[1]}"
  # host:port (single colon, numeric port) -> host   (leaves multi-colon IPv6 intact)
  elif [[ "$t" =~ ^([^:]+):[0-9]+$ ]]; then
    t="${BASH_REMATCH[1]}"
  fi
  t="${t%.}"          # trailing dot on FQDN
  printf '%s' "$t" | tr 'A-Z' 'a-z'
}

classify_target() {
  local t="$1"
  if [[ "$t" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then echo ipv4; return; fi
  if [[ "$t" == *:* ]]; then echo ipv6; return; fi
  if [[ "$t" == *.*[a-z]* || "$t" == *[a-z]*.* ]]; then echo domain; return; fi
  echo unknown
}

is_rate_limited() {
  # Heuristic: does the response look like a throttle/quota message?
  printf '%s' "$1" | grep -qiE \
    'rate limit|query rate|queries exceeded|limit exceeded|too many|quota|temporarily (denied|blocked)|please (wait|try again)|slow down|throttl'
}

respect_rate_limit() {
  # Ensure at least MIN_SERVER_INTERVAL seconds since we last hit $1.
  local server="$1" now last wait
  [[ -z "$server" ]] && return 0
  now=$(date +%s)
  last="${LAST_HIT[$server]:-0}"
  wait=$(( MIN_SERVER_INTERVAL - (now - last) ))
  if (( wait > 0 )); then sleep "$wait"; fi
  LAST_HIT[$server]=$(date +%s)
}

run_whois() {
  # $1 server (may be empty -> client default), $2 target.
  # Retries on timeout or rate-limit with growing backoff.
  # Prints response to stdout; returns whois exit code (124 = timed out).
  local server="$1" target="$2" attempt=1 out rc backoff
  while :; do
    respect_rate_limit "$server"
    if [[ -n "$server" ]]; then
      if out=$(timeout -k 3 "$CONNECT_TIMEOUT" whois -h "$server" -- "$target" </dev/null 2>&1); then rc=0; else rc=$?; fi
    else
      if out=$(timeout -k 3 "$CONNECT_TIMEOUT" whois -- "$target" </dev/null 2>&1); then rc=0; else rc=$?; fi
    fi

    if { (( rc == 124 || rc == 137 )) || is_rate_limited "$out"; } && (( attempt <= MAX_RETRIES )); then
      backoff=$(( BASE_BACKOFF * attempt ))
      log "  ! ${target}${server:+ @ $server}: $( (( rc == 124 || rc == 137 )) && echo timed out || echo rate-limited ), retry ${attempt}/${MAX_RETRIES} in ${backoff}s"
      sleep "$backoff"
      (( attempt++ ))
      continue
    fi
    printf '%s' "$out"
    return "$rc"
  done
}

extract_iana_refer() {
  # From an IANA response, pull the authoritative server (refer:/whois:).
  grep -iE '^[[:space:]]*(refer|whois):[[:space:]]*[^[:space:]]' \
    | head -n1 \
    | sed -E 's/^[[:space:]]*[^:]+:[[:space:]]*//' \
    | sed 's#[/:].*$##' \
    | tr -d '[:space:]'
}

extract_referral_host() {
  # From a registry response, find the next hop:
  #   ARIN IP style : "ReferralServer: whois://host"
  #   Domain style  : "Registrar WHOIS Server: host"
  local out host
  out="$(cat)"
  host="$(printf '%s\n' "$out" | grep -iE 'ReferralServer:[[:space:]]*whois://' | head -n1 \
          | sed -E 's#.*whois://##' | sed 's#[/:].*$##' | tr -d '[:space:]')"
  if [[ -z "$host" ]]; then
    host="$(printf '%s\n' "$out" | grep -iE 'Registrar WHOIS Server:[[:space:]]*[^[:space:]]' | head -n1 \
            | sed -E 's/.*:[[:space:]]*//' | sed 's#[/:].*$##' | tr -d '[:space:]')"
  fi
  printf '%s' "$host"
}

get_authoritative_server() {
  # Ask IANA which server is authoritative for this target (works for TLDs & IPs).
  local target="$1" kind="$2" iana srv
  iana=$(run_whois "whois.iana.org" "$target" || true)
  srv=$(printf '%s\n' "$iana" | extract_iana_refer || true)
  if [[ -n "$srv" ]]; then printf '%s' "$srv"; return 0; fi
  # No IANA answer: for IPs, fall back to ARIN; for domains, let the client decide.
  case "$kind" in
    ipv4|ipv6) printf '%s' "${FALLBACK_SERVERS[0]}" ;;
    *)         printf '%s' "" ;;
  esac
}

# --- Argument handling ---
if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
  sed -n '4,20p' "$0" >&2
  [[ $# -eq 0 ]] && exit 1 || exit 0
fi

input_file=$1
if [[ "$input_file" == "-" ]]; then
  input_file=/dev/stdin
elif [[ ! -f "$input_file" ]]; then
  err "Input file '$input_file' not found."
  exit 1
fi

# Guard against the classic `./bulkwhois.sh ips.txt > ips.txt` self-truncation.
if [[ -n "$OUTPUT_FILE" ]]; then
  if [[ "$input_file" != "/dev/stdin" ]] && [[ "$OUTPUT_FILE" -ef "$input_file" ]] 2>/dev/null; then
    err "OUTPUT_FILE is the same as the input file. Refusing to overwrite it."
    exit 1
  fi
  exec > "$OUTPUT_FILE"
fi

# --- Main loop ---
total=0; done_ok=0; skipped=0
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line=$(trim "$raw")
  [[ -z "$line" ]] && continue
  [[ "$line" == \#* ]] && continue

  target=$(normalize_target "$line")
  kind=$(classify_target "$target")
  total=$(( total + 1 ))

  if [[ "$kind" == "unknown" ]]; then
    err "Skipping unrecognized input: '$line'"
    skipped=$(( skipped + 1 ))
    echo "===================================================================="
    continue
  fi

  log "[$total] $target ($kind)"
  echo "===================================================================="
  echo "WHOIS lookup for: $target   [$kind]"

  primary_srv=$(get_authoritative_server "$target" "$kind")
  [[ -n "$primary_srv" ]] && echo "(server: $primary_srv)"

  first=$(run_whois "$primary_srv" "$target" || true)
  printf '%s\n' "$first"

  # Follow referral hops (registry -> registrar for domains, ARIN -> RIR for IPs).
  prev_srv="$primary_srv"
  current="$first"
  for (( hop = 1; hop <= MAX_REFERRALS; hop++ )); do
    referral=$(printf '%s\n' "$current" | extract_referral_host || true)
    [[ -z "$referral" ]] && break
    [[ "$referral" == "$prev_srv" ]] && break
    echo
    echo "---- Following referral -> $referral ----"
    current=$(run_whois "$referral" "$target" || true)
    printf '%s\n' "$current"
    prev_srv="$referral"
  done

  done_ok=$(( done_ok + 1 ))
  echo "===================================================================="
  (( SLEEP_BETWEEN > 0 )) && sleep "$SLEEP_BETWEEN"
done < "$input_file"

log ""
log "Done. $done_ok completed, $skipped skipped, $total total."
