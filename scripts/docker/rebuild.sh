#!/bin/bash
# ===========================================
# Rebuild Docker Services (pull + restart)
# ===========================================
# Usage:
#   ./scripts/docker/rebuild.sh                      # Rebuild all services
#   ./scripts/docker/rebuild.sh traefik homepage     # Rebuild specific services

set -e

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

check_env

services=($(get_services "$@"))

if [[ $# -eq 0 ]]; then
    print_box "REBUILDING ALL SERVICES"
else
    print_box "REBUILDING: ${services[*]}"
fi

for service in "${services[@]}"; do
    if [[ -d "$SERVICES_DIR/$service" ]]; then
        do_rebuild "$service"
    fi
done

print_footer "Rebuild complete!"
