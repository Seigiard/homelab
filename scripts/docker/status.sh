#!/bin/bash
# ===========================================
# Show Docker Services Status
# ===========================================
# Usage:
#   ./scripts/docker/status.sh [service...]

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

print_box "SERVICE STATUS"

filters=()
for service in "$@"; do
    filters+=(--filter "label=com.docker.compose.project=$service")
done

docker ps "${filters[@]}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
