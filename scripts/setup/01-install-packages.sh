#!/bin/bash
# ===========================================
# Step 01: Install Packages
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 2/9: Installing packages"

packages=(
    # Essential
    curl
    wget
    # Editors
    micro
    # Terminal tools
    zellij
    htop
    mc
    tree
    ncdu
    jq
    # Network
    openssh-server
    avahi-daemon
    avahi-utils
    # Shell
    zsh
)

log_step "Installing: ${packages[*]}"
sudo apt install -y "${packages[@]}"

# Enable SSH
sudo systemctl enable ssh
sudo systemctl start ssh

log_info "Packages installed"
