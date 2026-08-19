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

# Service order (only services with dependencies)
# Other services are auto-discovered from services/*/docker-compose.yml
SERVICE_ORDER=(
    traefik      # Must be first - reverse proxy for all services
    authelia     # SSO - must be up before services that use auth middleware
    cloudflared  # Depends on traefik network
)

# -------------------------------------------
# Helper functions
# -------------------------------------------

# Auto-discover all services with docker-compose.yml
discover_services() {
    find "$SERVICES_DIR" -maxdepth 2 -name "docker-compose.yml" -exec dirname {} \; | \
        xargs -n1 basename | sort -u
}

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
# Returns: SERVICE_ORDER first, then auto-discovered services (alphabetically)
get_services() {
    if [[ $# -gt 0 ]]; then
        echo "$@"
        return
    fi

    local all_services=($(discover_services))
    local result=()

    # First: services from SERVICE_ORDER (preserving order)
    for ordered in "${SERVICE_ORDER[@]}"; do
        for svc in "${all_services[@]}"; do
            if [[ "$svc" == "$ordered" ]]; then
                result+=("$svc")
                break
            fi
        done
    done

    # Then: remaining services (not in SERVICE_ORDER)
    for svc in "${all_services[@]}"; do
        local in_order=false
        for ordered in "${SERVICE_ORDER[@]}"; do
            if [[ "$svc" == "$ordered" ]]; then
                in_order=true
                break
            fi
        done
        if [[ "$in_order" == "false" ]]; then
            result+=("$svc")
        fi
    done

    echo "${result[@]}"
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

# Expands ${VAR} and ${VAR:-default} the way Compose does.
# envsubst cannot replace this: it ignores the :-default form and leaves the
# whole ${VAR:-default} in place.
expand_compose_vars() {
    local rest="$1" out="" expr var default

    while [[ "$rest" == *'${'* ]]; do
        out+="${rest%%'${'*}"
        rest="${rest#*'${'}"
        expr="${rest%%\}*}"
        rest="${rest#*\}}"

        var="${expr%%:-*}"
        default=""
        [[ "$expr" == *":-"* ]] && default="${expr#*:-}"
        out+="${!var:-$default}"
    done

    printf '%s' "$out$rest"
}

# Creates directories from docker-compose volumes with correct ownership
# This prevents Docker from creating them as root:root
ensure_service_dirs() {
    local compose_file="$1"

    # Load environment variables
    set -a
    source "$PROJECT_DIR/.env"
    set +a

    # Extract host paths from volumes (format: ${VAR}/path:/container/path or /absolute/path:/container/path)
    # Variables expand first: ${VAR:-default} carries its own colon, so the
    # host/container split is only unambiguous after expansion.
    grep -E '^[[:space:]]*-[[:space:]]*(\$\{|/)' "$compose_file" 2>/dev/null | \
    sed -E 's/^[[:space:]]*-[[:space:]]*//' | \
    while IFS= read -r volume; do
        local host_path
        host_path="$(expand_compose_vars "$volume")"
        host_path="${host_path%%:*}"

        # Skip named volumes and unexpanded relative defaults
        [[ -n "$host_path" && "$host_path" == /* ]] || continue

        # Never materialize host system paths that a service only reads
        case "$host_path" in
            /|/dev/*|/etc/*|/proc/*|/run/*|/sys/*|/var/run/*) continue ;;
        esac

        if [[ ! -e "$host_path" ]]; then
            sudo install -d -m 755 -o "${PUID:-1000}" -g "${PGID:-1000}" "$host_path"
            log_info "Created directory: $host_path"
        fi
    done
}

# Aborts if the service stores data on a filesystem that fstab knows but is not
# mounted (e.g. the RAID1 mirror failed to assemble; fstab carries `nofail`, so
# boot succeeds and /mnt/data is an empty directory on the root filesystem).
# Without this, Docker creates the bind-mount sources there and services run on
# an empty tree while writing to the system disk.
check_data_mount() {
    local compose_file="$1"

    grep -q 'DATA_PATH' "$compose_file" 2>/dev/null || return 0

    local data_path
    data_path=$(grep -E '^DATA_PATH=' "$PROJECT_DIR/.env" | tail -1 | cut -d= -f2-)
    data_path="${data_path%/}"
    [[ -n "$data_path" ]] || return 0

    # Only guard paths fstab declares as their own mount point
    findmnt --fstab -T "$data_path" >/dev/null 2>&1 || return 0

    if ! mountpoint -q "$data_path"; then
        log_error "$data_path is in /etc/fstab but not mounted — refusing to deploy."
        log_error "Data would land on the root filesystem. Check: cat /proc/mdstat; sudo mount -a"
        return 1
    fi
}

do_deploy() {
    local service="$1"
    validate_service "$service" || return 1
    check_data_mount "$SERVICES_DIR/$service/docker-compose.yml" || return 1

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

do_remove() {
    local service="$1"
    local service_dir="$SERVICES_DIR/$service"
    local compose_file="$service_dir/docker-compose.yml"

    if [[ -f "$compose_file" ]]; then
        log_step "Removing $service (down + image cleanup)..."
        docker compose -f "$compose_file" --env-file "$PROJECT_DIR/.env" down --rmi all 2>/dev/null
    else
        log_step "Removing $service containers and images..."
        docker rm -f "$service" 2>/dev/null || true
        local images
        images=$(docker images --filter "reference=*$service*" -q)
        if [[ -n "$images" ]]; then
            docker image rm $images 2>/dev/null || true
        fi
    fi
    log_info "$service removed"
}

do_purge() {
    local service="$1"

    set -a
    source "$PROJECT_DIR/.env"
    set +a

    local appdata_dir="${APPDATA_PATH:-/opt/homelab/appdata}/$service"

    if [[ ! -d "$appdata_dir" ]]; then
        log_warn "No appdata directory for $service ($appdata_dir)"
        return 0
    fi

    log_warn "Will delete: $appdata_dir"
    if confirm "Delete appdata for $service?" "n"; then
        sudo rm -rf "$appdata_dir"
        log_info "$service appdata purged"
    else
        log_info "Skipped appdata deletion for $service"
    fi
}

do_rebuild() {
    local service="$1"
    validate_service "$service" || return 1
    check_data_mount "$SERVICES_DIR/$service/docker-compose.yml" || return 1

    # Ensure directories exist with correct ownership
    ensure_service_dirs "$SERVICES_DIR/$service/docker-compose.yml"

    log_step "Rebuilding $service..."
    docker compose -f "$SERVICES_DIR/$service/docker-compose.yml" --env-file "$PROJECT_DIR/.env" down
    docker compose -f "$SERVICES_DIR/$service/docker-compose.yml" --env-file "$PROJECT_DIR/.env" pull
    docker compose -f "$SERVICES_DIR/$service/docker-compose.yml" --env-file "$PROJECT_DIR/.env" up -d
    log_info "$service rebuilt"
}
