#!/bin/bash
# ===========================================
# Remove Docker Services
# ===========================================
# Usage:
#   ./scripts/docker/remove.sh myservice           # Stop + remove images
#   ./scripts/docker/remove.sh --purge myservice    # + delete appdata

set -e

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

PURGE=false
services=()

for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=true ;;
        *) services+=("$arg") ;;
    esac
done

if [[ ${#services[@]} -eq 0 ]]; then
    log_error "Usage: remove.sh [--purge] <service> [service...]"
    log_error "Specify service names explicitly (no 'remove all' for safety)"
    exit 1
fi

check_env

if [[ "$PURGE" == "true" ]]; then
    print_box "REMOVING + PURGING: ${services[*]}"
else
    print_box "REMOVING: ${services[*]}"
fi

for service in "${services[@]}"; do
    do_remove "$service"
    if [[ "$PURGE" == "true" ]]; then
        do_purge "$service"
    fi
done

print_footer "Remove complete!"
