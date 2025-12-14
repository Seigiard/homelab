#!/bin/bash
# ===========================================
# Deploy Docker Services
# ===========================================
# Usage:
#   ./scripts/docker/deploy.sh                      # Deploy all services
#   ./scripts/docker/deploy.sh traefik homepage     # Deploy specific services

set -e

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

check_env

services=($(get_services "$@"))

if [[ $# -eq 0 ]]; then
    print_box "DEPLOYING ALL SERVICES"
else
    print_box "DEPLOYING: ${services[*]}"
fi

for service in "${services[@]}"; do
    if [[ -d "$SERVICES_DIR/$service" ]]; then
        do_deploy "$service"
    fi
done

print_footer "Deploy complete!"
echo ""
log_info "Dashboard: http://home.local"
