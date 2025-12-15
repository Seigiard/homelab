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

# -------------------------------------------
# APT packages
# -------------------------------------------

log_step "Installing apt packages: ${APT_PACKAGES[*]}"
sudo apt install -y "${APT_PACKAGES[@]}"

# Verify packages installed
log_step "Verifying installed packages..."
for pkg in "${APT_PACKAGES[@]}"; do
    require_package "$pkg"
done
log_info "APT packages installed"

# -------------------------------------------
# Snap packages
# -------------------------------------------

for pkg in "${SNAP_PACKAGES[@]}"; do
    if ! command -v "$pkg" &> /dev/null; then
        if [[ "${TEST_MODE:-0}" == "1" ]]; then
            log_info "[TEST] Skipping $pkg snap install"
        else
            log_step "Installing $pkg via snap..."
            sudo snap install "$pkg" --classic
            require_command "$pkg"
            log_info "$pkg installed"
        fi
    else
        log_info "$pkg already installed"
    fi
done

# -------------------------------------------
# Cargo packages
# -------------------------------------------

if [[ ${#CARGO_PACKAGES[@]} -gt 0 ]]; then
    log_step "Installing cargo packages: ${CARGO_PACKAGES[*]}"
    for pkg in "${CARGO_PACKAGES[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            cargo install "$pkg"
            log_info "$pkg installed"
        else
            log_info "$pkg already installed"
        fi
    done
fi

# -------------------------------------------
# Enable services
# -------------------------------------------

sudo systemctl enable ssh
sudo systemctl start ssh

log_info "Package installation complete"
