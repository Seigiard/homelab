#!/bin/bash
# ===========================================
# Stop Docker Services
# ===========================================
# Usage:
#   ./scripts/docker/stop.sh                      # Stop all services
#   ./scripts/docker/stop.sh traefik homepage     # Stop specific services

set -e

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

services=($(get_services "$@"))

# Reverse order for stopping (dependencies last)
if [[ $# -eq 0 ]]; then
    print_box "STOPPING ALL SERVICES"
    services=($(get_services_reversed "${services[@]}"))
else
    print_box "STOPPING: ${services[*]}"
fi

for service in "${services[@]}"; do
    if [[ -d "$SERVICES_DIR/$service" ]]; then
        do_stop "$service"
    fi
done

print_footer "All services stopped"
