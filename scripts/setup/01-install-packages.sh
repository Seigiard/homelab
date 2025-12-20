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
# Lazygit (via PPA)
# -------------------------------------------

if ! command -v lazygit &> /dev/null; then
    log_step "Installing lazygit via PPA..."
    sudo add-apt-repository -y ppa:lazygit-team/release
    sudo apt update
    sudo apt install -y lazygit
    log_info "lazygit installed"
else
    log_info "lazygit already installed: $(lazygit --version)"
fi

# -------------------------------------------
# Rust (via rustup)
# -------------------------------------------

if ! command -v cargo &> /dev/null; then
    log_step "Installing Rust via rustup..."
    # Remove old system packages if present
    sudo apt remove -y cargo rustc 2>/dev/null || true
    # Install rustup (non-interactive)
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    log_info "Rust $(cargo --version) installed"
else
    log_info "Rust already installed: $(cargo --version)"
fi

# -------------------------------------------
# Cargo packages
# -------------------------------------------

if [[ ${#CARGO_PACKAGES[@]} -gt 0 ]]; then
    # Ensure cargo is in PATH
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

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
