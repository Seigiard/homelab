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

log_step "Installing apt packages: ${packages[*]}"
sudo apt install -y "${packages[@]}"

# Verify packages installed
log_step "Verifying installed packages..."
for pkg in "${packages[@]}"; do
    require_package "$pkg"
done
log_info "All packages installed"

# Install zellij via snap (not in Ubuntu apt repos)
if ! command -v zellij &> /dev/null; then
    if [[ "${TEST_MODE:-0}" == "1" ]]; then
        log_info "[TEST] Skipping zellij snap install"
    else
        log_step "Installing zellij via snap..."
        sudo snap install zellij --classic
        require_command zellij
        log_info "Zellij installed"
    fi
else
    log_info "Zellij already installed"
fi

# Enable SSH
sudo systemctl enable ssh
sudo systemctl start ssh

log_info "Setup complete"
