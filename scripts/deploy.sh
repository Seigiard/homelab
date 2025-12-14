#!/bin/bash
# ===========================================
# Deploy Homelab Services
# ===========================================
# Usage:
#   ./scripts/deploy.sh          # Start all services
#   ./scripts/deploy.sh traefik  # Start specific service
#   ./scripts/deploy.sh stop     # Stop all services
#   ./scripts/deploy.sh rebuild  # Pull new images and restart

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVICES_DIR="$PROJECT_DIR/services"

source "$SCRIPT_DIR/lib/tui.sh"

# Service start order (dependencies first)
SERVICE_ORDER=(
    traefik
    homepage
    cloudflared
    # Add more services here in dependency order
)

# -------------------------------------------

start_service() {
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

    log_step "Starting $service..."
    docker compose -f "$service_dir/docker-compose.yml" --env-file "$PROJECT_DIR/.env" up -d
    log_info "$service started"
}

stop_service() {
    local service="$1"
    local service_dir="$SERVICES_DIR/$service"

    if [[ -f "$service_dir/docker-compose.yml" ]]; then
        log_step "Stopping $service..."
        docker compose -f "$service_dir/docker-compose.yml" --env-file "$PROJECT_DIR/.env" down
        log_info "$service stopped"
    fi
}

rebuild_service() {
    local service="$1"
    local service_dir="$SERVICES_DIR/$service"

    if [[ ! -d "$service_dir" ]]; then
        log_error "Service not found: $service"
        return 1
    fi

    log_step "Rebuilding $service..."
    docker compose -f "$service_dir/docker-compose.yml" --env-file "$PROJECT_DIR/.env" down
    docker compose -f "$service_dir/docker-compose.yml" --env-file "$PROJECT_DIR/.env" pull
    docker compose -f "$service_dir/docker-compose.yml" --env-file "$PROJECT_DIR/.env" up -d
    log_info "$service rebuilt"
}

start_all() {
    print_box "DEPLOYING SERVICES"

    # Check .env exists
    if [[ ! -f "$PROJECT_DIR/.env" ]]; then
        log_error ".env file not found. Copy from .env.example:"
        log_error "  cp $PROJECT_DIR/.env.example $PROJECT_DIR/.env"
        exit 1
    fi

    # Start services in order
    for service in "${SERVICE_ORDER[@]}"; do
        if [[ -d "$SERVICES_DIR/$service" ]]; then
            start_service "$service"
        fi
    done

    print_footer "All services deployed!"
    echo ""
    log_info "Dashboard: https://home.local"
}

stop_all() {
    print_box "STOPPING SERVICES"

    # Stop in reverse order
    for (( i=${#SERVICE_ORDER[@]}-1; i>=0; i-- )); do
        service="${SERVICE_ORDER[$i]}"
        if [[ -d "$SERVICES_DIR/$service" ]]; then
            stop_service "$service"
        fi
    done

    print_footer "All services stopped"
}

status() {
    print_box "SERVICE STATUS"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

rebuild_all() {
    print_box "REBUILDING SERVICES"

    for service in "${SERVICE_ORDER[@]}"; do
        if [[ -d "$SERVICES_DIR/$service" ]]; then
            rebuild_service "$service"
        fi
    done

    print_footer "All services rebuilt!"
}

# -------------------------------------------
# Main
# -------------------------------------------

case "${1:-}" in
    "")
        start_all
        ;;
    "stop")
        if [[ -n "${2:-}" ]]; then
            stop_service "$2"
        else
            stop_all
        fi
        ;;
    "status")
        status
        ;;
    "restart")
        if [[ -n "${2:-}" ]]; then
            stop_service "$2"
            start_service "$2"
        else
            stop_all
            start_all
        fi
        ;;
    "rebuild")
        if [[ -n "${2:-}" ]]; then
            rebuild_service "$2"
        else
            rebuild_all
        fi
        ;;
    *)
        # Start specific service
        start_service "$1"
        ;;
esac
