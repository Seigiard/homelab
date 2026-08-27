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

# A failing service must not abort the run: set -e used to skip every service
# after the failure without a word. An unknown name reached the same silence,
# because the directory guard here returned before validate_service could
# report it. do_rebuild validates and reports; record what it rejects.
failed=()

for service in "${services[@]}"; do
    do_rebuild "$service" || failed+=("$service")
done

if [[ ${#failed[@]} -gt 0 ]]; then
    print_footer "Rebuild finished with errors"
    log_error "Failed: ${failed[*]}"
    exit 1
fi

print_footer "Rebuild complete!"
