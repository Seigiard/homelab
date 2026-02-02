#!/bin/bash
# ===========================================
# Homelab Bootstrap Script
# ===========================================
# Run this script once on a fresh Ubuntu Server
# Usage: sudo ./scripts/bootstrap.sh
#
# This script:
# - Installs Docker and Docker Compose
# - Creates directory structure
# - Sets up users and permissions
# - Configures firewall

set -e  # Exit on error

# -------------------------------------------
# Load TUI library
# -------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TUI_LIB="$SCRIPT_DIR/lib/tui.sh"

if [[ -f "$TUI_LIB" ]]; then
    source "$TUI_LIB"
else
    # Fallback if tui.sh not found
    echo "[!] Warning: tui.sh not found, using basic output"
    log_info() { echo "[✓] $1"; }
    log_warn() { echo "[!] $1"; }
    log_error() { echo "[✗] $1"; }
    log_step() { echo "[→] $1"; }
fi

# -------------------------------------------
# Helper functions
# -------------------------------------------

check_root() {
    if ! is_root; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# -------------------------------------------
# Load configuration
# -------------------------------------------

PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
    log_info "Loaded configuration from .env"
else
    log_error ".env file not found. Copy .env.example to .env and configure it first."
    log_info "Run: cp .env.example .env"
    exit 1
fi

# Default values if not set
APPDATA_PATH="${APPDATA_PATH:-/opt/homelab/appdata}"
DATA_PATH="${DATA_PATH:-/mnt/data}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# -------------------------------------------
# Install Docker
# -------------------------------------------

install_docker() {
    if has_command docker; then
        log_info "Docker is already installed: $(docker --version)"
        return 0
    fi

    log_info "Installing Docker..."

    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Install prerequisites
    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Start and enable Docker
    systemctl start docker
    systemctl enable docker

    log_info "Docker installed successfully: $(docker --version)"
}

# -------------------------------------------
# Create directory structure
# -------------------------------------------

create_directories() {
    log_info "Creating directory structure..."

    # Appdata directories (for container configs)
    mkdir -p "$APPDATA_PATH"/{traefik,adguard,samba,immich,syncthing,homepage,monitoring}

    # Data directories
    mkdir -p "$DATA_PATH"/public/{movies,tv,music,.torrents-temp}
    mkdir -p "$DATA_PATH"/users/andrew/{files,photos,sync}
    mkdir -p "$DATA_PATH"/users/yuliia/{files,photos,sync}
    mkdir -p "$DATA_PATH"/backups

    log_info "Directory structure created"
}

# -------------------------------------------
# Set permissions
# -------------------------------------------

set_permissions() {
    log_info "Setting permissions..."

    # Appdata - owned by docker user
    chown -R "$PUID:$PGID" "$APPDATA_PATH"
    chmod -R 755 "$APPDATA_PATH"

    # Public - readable by everyone, writable by group
    chown -R "$PUID:$PGID" "$DATA_PATH/public"
    chmod -R 775 "$DATA_PATH/public"

    # User directories - private to each user
    chown -R "$PUID:$PGID" "$DATA_PATH/users/andrew"
    chmod -R 750 "$DATA_PATH/users/andrew"

    chown -R "$PUID:$PGID" "$DATA_PATH/users/yuliia"
    chmod -R 750 "$DATA_PATH/users/yuliia"

    # Backups
    chown -R "$PUID:$PGID" "$DATA_PATH/backups"
    chmod -R 750 "$DATA_PATH/backups"

    log_info "Permissions set"
}

# -------------------------------------------
# Create Docker network
# -------------------------------------------

create_docker_network() {
    # Skip in test mode (no Docker daemon running)
    if [[ "${TEST_MODE:-0}" == "1" ]]; then
        log_info "[TEST] Skipping Docker network creation"
        return 0
    fi

    if docker network inspect traefik-net &> /dev/null; then
        log_info "Docker network 'traefik-net' already exists"
    else
        log_info "Creating Docker network 'traefik-net'..."
        docker network create traefik-net
        log_info "Docker network created"
    fi
}

# -------------------------------------------
# Configure firewall
# -------------------------------------------

configure_firewall() {
    # Skip in test mode (UFW may not work in Docker)
    if [[ "${TEST_MODE:-0}" == "1" ]]; then
        log_info "[TEST] Skipping firewall configuration"
        return 0
    fi

    if ! has_command ufw; then
        log_warn "UFW not installed, skipping firewall configuration"
        return 0
    fi

    log_info "Configuring firewall..."

    # Allow SSH
    ufw allow ssh

    # HTTP/HTTPS for Traefik
    ufw allow 80/tcp
    ufw allow 443/tcp

    # DNS for AdGuard
    ufw allow 53/tcp
    ufw allow 53/udp

    # Samba
    ufw allow 137/udp
    ufw allow 138/udp
    ufw allow 139/tcp
    ufw allow 445/tcp

    # Torrent (Transmission peer ports)
    ufw allow 51413/tcp
    ufw allow 51413/udp
    ufw allow 51414/tcp
    ufw allow 51414/udp

    # Enable firewall (non-interactive)
    echo "y" | ufw enable

    log_info "Firewall configured"
}

# -------------------------------------------
# Add current user to docker group
# -------------------------------------------

setup_docker_user() {
    # Skip in test mode
    if [[ "${TEST_MODE:-0}" == "1" ]]; then
        log_info "[TEST] Skipping Docker user setup"
        return 0
    fi

    SUDO_USER_NAME="${SUDO_USER:-$USER}"

    if id -nG "$SUDO_USER_NAME" | grep -qw "docker"; then
        log_info "User '$SUDO_USER_NAME' is already in docker group"
    else
        log_info "Adding user '$SUDO_USER_NAME' to docker group..."
        usermod -aG docker "$SUDO_USER_NAME"
        log_info "User added to docker group. Please log out and back in for changes to take effect."
    fi
}

# -------------------------------------------
# Main
# -------------------------------------------

main() {
    print_box "HOMELAB BOOTSTRAP"

    check_root

    log_step "Starting bootstrap process..."

    print_header "Installing Docker"
    install_docker

    print_header "Creating directories"
    create_directories

    print_header "Setting permissions"
    set_permissions

    print_header "Creating Docker network"
    create_docker_network

    print_header "Configuring firewall"
    configure_firewall

    print_header "Setting up Docker user"
    setup_docker_user

    print_footer "Bootstrap completed!"

    log_info "Next steps:"
    echo "      1. Log out and back in (for docker group)"
    echo "      2. Run: ./scripts/deploy.sh"
    echo ""
}

main "$@"
