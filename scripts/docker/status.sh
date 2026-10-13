#!/bin/bash
# ===========================================
# Show Docker Services Status
# ===========================================
# Usage:
#   ./scripts/docker/status.sh [service...]

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

print_box "SERVICE STATUS"

if (($# == 0)); then
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    exit
fi

for service in "$@"; do
    docker ps --filter "label=com.docker.compose.project=$service" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
done
