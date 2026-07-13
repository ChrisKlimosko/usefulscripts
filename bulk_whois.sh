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
# auto  = only follow the registrar referral when the registry gave a THIN answer
#         (thick registries like CIRA already return the full record, so following
#         just duplicates it and wastes a query). always = always follow.
#         never = never follow.
FOLLOW_REFERRALS="${FOLLOW_REFERRALS:-auto}"
OUTPUT_FILE="${OUTPUT_FILE:-}"


# --- Shared state ---
# NOTE: run_whois/get_authoritative_server get called inside $( ) command
# substitutions, which run in SUBSHELLS. Bash associative arrays written in a
# subshell are lost when it exits, so rate-limit timestamps and the server cache
# MUST live on disk to survive. (This is not premature cleverness; using plain
# arrays here silently breaks both features.)
STATE_DIR="$(mktemp -d)"

_key() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

state_get() { local f="$STATE_DIR/$(_key "$1")"; [[ -f "$f" ]] && cat "$f"; }
state_has() { [[ -f "$STATE_DIR/$(_key "$1")" ]]; }
state_set() { printf '%s' "$2" > "$STATE_DIR/$(_key "$1")"; }

FALLBACK_SERVERS=(whois.arin.net whois.ripe.net whois.apnic.net whois.lacnic.net whois.afrinic.net)

# --- Logging (always to stderr so it never pollutes results) ---
log()  { printf '%s\n' "$*" >&2; }
err()  { printf 'ERROR: %s\n' "$*" >&2; }

# --- Clean exit on Ctrl-C / kill, and always remove the temp state dir ---
cleanup_state() { [[ -n "${STATE_DIR:-}" ]] && rm -rf "$STATE_DIR"; }
on_interrupt()  { log ""; log "Interrupted — stopping."; cleanup_state; exit 130; }
trap on_interrupt INT TERM
trap cleanup_state EXIT

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
  # Uses on-disk state so it works even when called from a subshell.
  local server="$1" now last wait
  [[ -z "$server" ]] && return 0
  now=$(date +%s)
  last="$(state_get "hit:$server")"
  last="${last:-0}"
  wait=$(( MIN_SERVER_INTERVAL - (now - last) ))
  if (( wait > 0 )); then sleep "$wait"; fi
  state_set "hit:$server" "$(date +%s)"
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

looks_thin() {
  # A registry response is "thin" if it carries essentially no contact record.
  # Thick registries (e.g. CIRA) include Registrant/Admin/Tech sections — even
  # when the values are REDACTED, the field labels are present. If those labels
  # exist, the registrar referral would only duplicate what we already have.
  ! printf '%s\n' "$1" | grep -qiE '^[[:space:]]*(Registrant|Admin|Tech|Billing) (Name|Organization|Email|Street|Country|Phone)'
}

_meaningful_lines() {
  # Canonicalize a whois record for comparison: drop legal/comment/volatile
  # boilerplate, trim, lowercase, sort-unique. Reads stdin.
  grep -vE '^[[:space:]]*[%#]' \
    | grep -vE '^[[:space:]]*>>>' \
    | grep -viE 'last update of whois|for more information on whois|icann whois inaccuracy|terms of use|legal notice|registration authority|please visit|governed by' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -vE '^$' \
    | tr 'A-Z' 'a-z' \
    | sort -u
}

referral_is_redundant() {
  # Return 0 (redundant) if >=90% of the referral record's meaningful lines
  # already appear in what we've printed so far. $1 = prior text, $2 = referral.
  local a b bcount common
  a=$(printf '%s\n' "$1" | _meaningful_lines)
  b=$(printf '%s\n' "$2" | _meaningful_lines)
  bcount=$(printf '%s\n' "$b" | grep -cvE '^$')
  (( bcount == 0 )) && return 0
  common=$(comm -12 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | grep -cvE '^$')
  (( common * 100 >= bcount * 90 ))
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
  # Cached on disk: for domains the key is the TLD, so 20 .ca domains cost
  # exactly ONE IANA query, not 20.
  local target="$1" kind="$2" key iana srv

  case "$kind" in
    domain) key="srv:tld:${target##*.}" ;;   # example.ca -> srv:tld:ca
    *)      key="srv:ip:${target}" ;;        # IPs must be resolved individually
  esac

  if state_has "$key"; then
    state_get "$key"
    return 0
  fi

  iana=$(run_whois "whois.iana.org" "$target" || true)
  srv=$(printf '%s\n' "$iana" | extract_iana_refer || true)

  if [[ -z "$srv" ]]; then
    # No IANA answer: for IPs fall back to ARIN; for domains let the whois
    # client do its own TLD routing (empty string = client default).
    case "$kind" in
      ipv4|ipv6) srv="${FALLBACK_SERVERS[0]}" ;;
      *)         srv="" ;;
    esac
  fi

  state_set "$key" "$srv"   # cache negatives too, so we don't retry a dead end
  printf '%s' "$srv"
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

  # Decide whether to chase the registrar referral at all.
  #   never  -> skip entirely
  #   always -> follow (still suppressed if it turns out to be a duplicate)
  #   auto   -> only when the registry answer was thin (missing a contact block)
  follow_ok=0
  case "$FOLLOW_REFERRALS" in
    always) follow_ok=1 ;;
    never)  follow_ok=0 ;;
    auto)   looks_thin "$first" && follow_ok=1 ;;
  esac

  if (( follow_ok )); then
    # Track every server queried for this target so we never hit one twice.
    declare -A visited=()
    visited["${primary_srv,,}"]=1
    seen="$first"          # everything shown so far, for redundancy checks
    current="$first"
    for (( hop = 1; hop <= MAX_REFERRALS; hop++ )); do
      referral=$(printf '%s\n' "$current" | extract_referral_host || true)
      [[ -z "$referral" ]] && break
      [[ -n "${visited[${referral,,}]+set}" ]] && break
      visited["${referral,,}"]=1

      resp=$(run_whois "$referral" "$target" || true)
      if referral_is_redundant "$seen" "$resp"; then
        echo
        echo "---- Referral $referral returned no new data (skipped) ----"
        break
      fi
      echo
      echo "---- Following referral -> $referral ----"
      printf '%s\n' "$resp"
      seen+=$'\n'"$resp"
      current="$resp"
    done
  fi

  done_ok=$(( done_ok + 1 ))
  echo "===================================================================="
  (( SLEEP_BETWEEN > 0 )) && sleep "$SLEEP_BETWEEN"
done < "$input_file"

log ""
log "Done. $done_ok completed, $skipped skipped, $total total."
