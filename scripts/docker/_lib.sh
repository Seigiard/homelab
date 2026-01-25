#!/bin/bash
# ===========================================
# Shared functions for Docker service management
# ===========================================

# Get project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
SERVICES_DIR="$PROJECT_DIR/services"

# Source TUI library
source "$PROJECT_DIR/scripts/lib/tui.sh"

# Service order (dependencies first)
SERVICE_ORDER=(
    traefik
    homepage
    cloudflared
    adguard
    glances
    dozzle
    samba
    filebrowser
    opds-generator
    jellyfin
    qbittorrent
    transmission
    backrest
    pricebuddy
)

# -------------------------------------------
# Helper functions
# -------------------------------------------

check_env() {
    if [[ ! -f "$PROJECT_DIR/.env" ]]; then
        log_error ".env file not found. Copy from .env.example:"
        log_error "  cp $PROJECT_DIR/.env.example $PROJECT_DIR/.env"
        exit 1
    fi
}

validate_service() {
    local service="$1"
    local service_dir="$SERVICES_DIR/$service"

    if [[ ! -d "$service_dir" ]]; then
        log_error "Service not found: $service"
        return 1
    fi

    if [[ ! -f "$service_dir/docker-compose.yml" ]]; then
        log_error "No docker-compose.yml in $service"
        return 1
    fi

    return 0
}

# Get services to operate on (from args or all)
# Usage: services=($(get_services "$@"))
get_services() {
    if [[ $# -eq 0 ]]; then
        echo "${SERVICE_ORDER[@]}"
    else
        echo "$@"
    fi
}

# Get services in reverse order (for stopping)
get_services_reversed() {
    local services=("$@")
    local reversed=()
    for (( i=${#services[@]}-1; i>=0; i-- )); do
        reversed+=("${services[$i]}")
    done
    echo "${reversed[@]}"
}

# -------------------------------------------
# Service operations
# -------------------------------------------

# Creates directories from docker-compose volumes with correct ownership
# This prevents Docker from creating them as root:root
ensure_service_dirs() {
    local compose_file="$1"

    # Load environment variables
    set -a
    source "$PROJECT_DIR/.env"
    set +a

    # Extract host paths from volumes (format: ${VAR}/path:/container/path or /absolute/path:/container/path)
    # Skip named volumes (no / at start after expansion)
    grep -E '^\s*-\s*(\$\{|/)' "$compose_file" 2>/dev/null | \
    sed -E 's/^\s*-\s*//; s/:.*$//' | \
    envsubst | while read -r host_path; do
        # Only process absolute paths that don't exist
        if [[ -n "$host_path" && "$host_path" == /* && ! -e "$host_path" ]]; then
            sudo install -d -m 755 -o "${PUID:-1000}" -g "${PGID:-1000}" "$host_path"
            log_info "Created directory: $host_path"
        fi
    done
}

do_deploy() {
    local service="$1"
    validate_service "$service" || return 1

    # Create directories BEFORE container starts to prevent root:root ownership
    ensure_service_dirs "$SERVICES_DIR/$service/docker-compose.yml"

    log_step "Deploying $service..."
    docker compose -f "$SERVICES_DIR/$service/docker-compose.yml" --env-file "$PROJECT_DIR/.env" up -d
    log_info "$service deployed"
}

do_stop() {
    local service="$1"
    local service_dir="$SERVICES_DIR/$service"

    if [[ -f "$service_dir/docker-compose.yml" ]]; then
        log_step "Stopping $service..."
        docker compose -f "$service_dir/docker-compose.yml" --env-file "$PROJECT_DIR/.env" down
        log_info "$service stopped"
    fi
}

do_rebuild() {
    local service="$1"
    validate_service "$service" || return 1

    # Ensure directories exist with correct ownership
    ensure_service_dirs "$SERVICES_DIR/$service/docker-compose.yml"

    log_step "Rebuilding $service..."
    docker compose -f "$SERVICES_DIR/$service/docker-compose.yml" --env-file "$PROJECT_DIR/.env" down
    docker compose -f "$SERVICES_DIR/$service/docker-compose.yml" --env-file "$PROJECT_DIR/.env" pull
    docker compose -f "$SERVICES_DIR/$service/docker-compose.yml" --env-file "$PROJECT_DIR/.env" up -d
    log_info "$service rebuilt"
}
