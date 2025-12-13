#!/bin/bash
# ===========================================
# Homelab Server Setup Script (Bootstrap)
# ===========================================
# Run on fresh Ubuntu Server:
#   curl -fsSL https://raw.githubusercontent.com/seigiard/homelab/main/scripts/setup.sh | bash
#
# This minimal script:
# - Installs git
# - Clones the homelab repository
# - Runs the full setup via scripts/setup/--init.sh

set -e

# -------------------------------------------
# Configuration
# -------------------------------------------

GITHUB_USER="seigiard"
GITHUB_REPO="homelab"
INSTALL_PATH="/opt/homelab"

# -------------------------------------------
# Minimal TUI functions (no tui.sh available yet)
# -------------------------------------------

log_info() { echo "[✓] $1"; }
log_error() { echo "[✗] $1"; }
log_step() { echo "[→] $1"; }

# -------------------------------------------
# Check requirements
# -------------------------------------------

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║  HOMELAB BOOTSTRAP                        ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

if [[ $EUID -eq 0 ]]; then
    log_error "Do not run this script as root. Run as regular user with sudo access."
    exit 1
fi

if ! command -v sudo &>/dev/null; then
    log_error "sudo is not installed"
    exit 1
fi

log_info "Running as user: $USER"

# Request sudo password upfront
log_step "Requesting sudo access..."
sudo -v

# -------------------------------------------
# Install git
# -------------------------------------------

log_step "Installing git..."
sudo apt update -qq
sudo apt install -y git

# -------------------------------------------
# Clone repository
# -------------------------------------------

if [[ -d "$INSTALL_PATH" ]]; then
    log_info "Repository already exists: $INSTALL_PATH"
    log_step "Pulling latest changes..."
    cd "$INSTALL_PATH" && git pull
else
    log_step "Creating directory..."
    sudo mkdir -p "$INSTALL_PATH"
    sudo chown "$USER:$USER" "$INSTALL_PATH"

    log_step "Cloning repository..."
    git clone "https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git" "$INSTALL_PATH"
fi

# -------------------------------------------
# Create symlink
# -------------------------------------------

if [[ ! -L "$HOME/homelab" ]]; then
    ln -s "$INSTALL_PATH" "$HOME/homelab"
    log_info "Symlink created: ~/homelab -> $INSTALL_PATH"
fi

# -------------------------------------------
# Run full setup
# -------------------------------------------

log_info "Repository cloned. Starting full setup..."
echo ""

exec "$INSTALL_PATH/scripts/setup/--init.sh"
