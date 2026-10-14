#!/bin/bash
# ===========================================
# Show Docker Services Status
# ===========================================
# Usage:
#   ./scripts/docker/status.sh [service...]

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

set -euo pipefail

print_box "SERVICE STATUS"

container_ids=()

if (($# == 0)); then
    ids=$(docker ps -a -q)
    if [[ -n $ids ]]; then
        while IFS= read -r container_id; do
            container_ids+=("$container_id")
        done <<< "$ids"
    fi
else
    for service in "$@"; do
        ids=$(docker ps -a -q --filter "label=com.docker.compose.project=$service")
        if [[ -n $ids ]]; then
            while IFS= read -r container_id; do
                container_ids+=("$container_id")
            done <<< "$ids"
        fi
    done
fi

printf '%-32s %-12s %-10s %-14s %-14s %s\n' \
    'NAME' 'STATE' 'RESTARTS' 'EXIT CODE' 'IMAGE ID' 'IMAGE CREATED'

if ((${#container_ids[@]} > 0)); then
    for container_id in "${container_ids[@]}"; do
        if ! container=$(docker inspect "$container_id"); then
            printf 'Skipping container %s: docker inspect failed\n' "$container_id" >&2
            continue
        fi
        image_id=$(printf '%s' "$container" | jq -r '.[0].Image')
        image=$(docker image inspect "$image_id")
        name=$(printf '%s' "$container" | jq -r '.[0].Name | ltrimstr("/")')
        state=$(printf '%s' "$container" | jq -r '.[0].State.Status // "-"')
        restarts=$(printf '%s' "$container" | jq -r '.[0].RestartCount')
        exit_code=$(printf '%s' "$container" | jq -r '.[0].State.ExitCode')
        image_created=$(printf '%s' "$image" | jq -r '.[0].Created')
        short_image_id=${image_id#sha256:}
        short_image_id=${short_image_id:0:12}

        printf '%-32s %-12s %-10s %-14s %-14s %s\n' \
            "$name" "$state" "$restarts" "$exit_code" "$short_image_id" "$image_created"
    done
fi
