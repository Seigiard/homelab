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
    glances
    dozzle
    samba
    filebrowser
    komga
    opds-generator
    # Add more services here in dependency order
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

do_deploy() {
    local service="$1"
    validate_service "$service" || return 1

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

    log_step "Rebuilding $service..."
    docker compose -f "$SERVICES_DIR/$service/docker-compose.yml" --env-file "$PROJECT_DIR/.env" down
    docker compose -f "$SERVICES_DIR/$service/docker-compose.yml" --env-file "$PROJECT_DIR/.env" pull
    docker compose -f "$SERVICES_DIR/$service/docker-compose.yml" --env-file "$PROJECT_DIR/.env" up -d
    log_info "$service rebuilt"
}
