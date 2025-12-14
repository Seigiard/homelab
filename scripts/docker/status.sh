#!/bin/bash
# ===========================================
# Show Docker Services Status
# ===========================================
# Usage:
#   ./scripts/docker/status.sh

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

print_box "SERVICE STATUS"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
