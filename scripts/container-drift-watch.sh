#!/bin/bash
# Notify Home Assistant after a container restarts repeatedly or changes image.

set -euo pipefail

STATE="${CONTAINER_DRIFT_STATE:-/var/lib/container-drift-watch/state.json}"
HA_WEBHOOK_URL="${HA_WEBHOOK_URL:-http://127.0.0.1:8123/api/webhook/homelab-container-drift}"

log() { logger -t container-drift-watch -p "daemon.$1" -- "$2"; }

notify() {
    local container=$1 event=$2 message=$3 body

    body=$(jq -cn --arg container "$container" --arg event "$event" --arg message "$message" \
        '{container: $container, event: $event, message: $message}')

    if ! curl --fail --silent --show-error --connect-timeout 5 --max-time 15 -X POST \
        -H 'Content-Type: application/json' --data "$body" "$HA_WEBHOOK_URL"; then
        log err "failed to notify Home Assistant about $event for $container"
        return 1
    fi
}

state_dir=$(dirname "$STATE")
mkdir -p "$state_dir"

has_previous_state=false
if [[ -e "$STATE" ]]; then
    if ! jq -e 'type == "array"' "$STATE" >/dev/null; then
        log err "state file is not a JSON array: $STATE"
        exit 1
    fi
    has_previous_state=true
fi

next_state=$(mktemp "$state_dir/container-drift-watch.XXXXXX")
trap 'rm -f "$next_state"' EXIT
printf '[\n' > "$next_state"
state_first=true

append_state() {
    if [[ $state_first == true ]]; then
        state_first=false
    else
        printf ',\n' >> "$next_state"
    fi
    printf '  %s' "$1" >> "$next_state"
}

failed=0
container_ids=()
ids=$(docker ps -a -q)
if [[ -n $ids ]]; then
    while IFS= read -r container_id; do
        container_ids+=("$container_id")
    done <<< "$ids"
fi

if ((${#container_ids[@]} > 0)); then
    for container_id in "${container_ids[@]}"; do
        container=$(docker inspect "$container_id")
        current=$(printf '%s' "$container" | jq -ce \
            '.[0] | {name: (.Name | ltrimstr("/")), image: .Image, restarts: .RestartCount}
             | select(.name != "" and (.image | type == "string") and (.restarts | type == "number"))')
        name=$(printf '%s' "$current" | jq -r '.name')
        image=$(printf '%s' "$current" | jq -r '.image')
        restarts=$(printf '%s' "$current" | jq -r '.restarts')

        if [[ $has_previous_state == false ]]; then
            append_state "$current"
            continue
        fi

        previous=$(jq -c --arg name "$name" '.[] | select(.name == $name)' "$STATE")
        if [[ -z $previous ]]; then
            append_state "$current"
            continue
        fi

        previous_image=$(printf '%s' "$previous" | jq -r '.image')
        previous_restarts=$(printf '%s' "$previous" | jq -r '.restarts')
        container_failed=0

        if (( restarts > previous_restarts )); then
            if ! notify "$name" restarts "Container $name restarted $((restarts - previous_restarts)) time(s) since the previous check."; then
                container_failed=1
                failed=1
            fi
        fi

        if [[ $container_failed == 0 && $image != "$previous_image" ]]; then
            if ! notify "$name" image "Container $name is running a different image than at the previous check."; then
                container_failed=1
                failed=1
            fi
        fi

        # Preserve this container's old state after a delivery failure so its alert retries.
        if [[ $container_failed == 1 ]]; then
            append_state "$previous"
        else
            append_state "$current"
        fi
    done
fi

printf '\n]\n' >> "$next_state"
mv "$next_state" "$STATE"
trap - EXIT

exit "$failed"
