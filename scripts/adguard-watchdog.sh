#!/bin/bash
# ===========================================
# AdGuard watchdog
# ===========================================
# The host resolver is a container: /etc/resolv.conf points at 127.0.0.1:53,
# which is adguard. When that container goes missing the whole machine loses
# DNS at once, and every other container with it -- Docker's embedded resolver
# has nothing left to forward to. That is how an image rebuild once left the
# Cloudflare tunnel crash-looping for twenty minutes with no one watching.
#
# Pause during deliberate maintenance:
#   sudo touch /run/adguard-watchdog.disabled

set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/homelab}"
STATE="${ADGUARD_WATCHDOG_STATE:-/run/adguard-watchdog/state}"
DISABLED="${ADGUARD_WATCHDOG_DISABLED:-/run/adguard-watchdog.disabled}"
PROBE_NAME="home.local"
MAX_ATTEMPTS=3
WINDOW=900

log() { logger -t adguard-watchdog -p "daemon.$1" -- "$2"; }

# Require an actual A record. dig prints its diagnostics (";; communications
# error ... connection refused") on stdout even with +short, so a non-empty
# reply is not evidence that anything answered.
resolver_answers() {
    dig +short "+time=$1" +tries=1 @127.0.0.1 "$PROBE_NAME" 2>/dev/null \
        | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
}

if [[ -e "$DISABLED" ]]; then
    exit 0
fi

# Probe a name adguard rewrites itself. Asking for a public name instead would
# turn every ISP outage into a pointless container restart.
if resolver_answers 2; then
    rm -f "$STATE" 2>/dev/null
    exit 0
fi

mkdir -p "$(dirname "$STATE")" 2>/dev/null

now=$(date +%s)
first=$now
count=0

if [[ -r "$STATE" ]]; then
    read -r first count < "$STATE"
    [[ "$first" =~ ^[0-9]+$ ]] || first=$now
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    if (( now - first > WINDOW )); then
        first=$now
        count=0
    fi
fi

# A resolver that dies again the moment it comes back is broken in a way this
# script cannot fix. Stop rather than restart it every minute forever.
if (( count >= MAX_ATTEMPTS )); then
    log err "resolver still silent after $count restarts within $((WINDOW / 60)) min -- giving up, this needs a human"
    exit 1
fi

count=$(( count + 1 ))
printf '%s %s\n' "$first" "$count" > "$STATE" 2>/dev/null

log err "no answer for $PROBE_NAME from 127.0.0.1:53 -- redeploying adguard (attempt $count/$MAX_ATTEMPTS)"

output=$("$PROJECT_DIR/scripts/docker/deploy.sh" adguard 2>&1)
rc=$?

if (( rc != 0 )); then
    log err "adguard redeploy failed (exit $rc): $(printf '%s' "$output" | tail -3 | tr '\n' ' ')"
    exit "$rc"
fi

# Confirm service, not exit status: compose reports success as soon as the
# container starts, which is before AdGuard binds port 53.
for _ in $(seq 1 15); do
    if resolver_answers 1; then
        log warning "adguard redeployed, resolver answering again"
        rm -f "$STATE" 2>/dev/null
        exit 0
    fi
    sleep 1
done

log err "adguard redeployed but the resolver is still silent"
exit 1
