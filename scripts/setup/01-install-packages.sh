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
# Lazygit (from GitHub releases)
# -------------------------------------------

if ! command -v lazygit &> /dev/null; then
    log_step "Installing lazygit from GitHub..."
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
    if [[ -z "$LAZYGIT_VERSION" || "$LAZYGIT_VERSION" == "null" ]]; then
        log_error "Failed to get lazygit version"
        exit 1
    fi
    curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xzf /tmp/lazygit.tar.gz -C /tmp lazygit
    sudo install /tmp/lazygit /usr/local/bin
    rm -f /tmp/lazygit /tmp/lazygit.tar.gz
    log_info "lazygit ${LAZYGIT_VERSION} installed"
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
# Starship (from GitHub releases)
# -------------------------------------------

if ! command -v starship &> /dev/null; then
    log_step "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    require_command "starship"
    log_info "starship $(starship --version | head -1) installed"
else
    log_info "starship already installed: $(starship --version | head -1)"
fi

# -------------------------------------------
# mise (polyglot version manager)
# -------------------------------------------

if ! command -v mise &> /dev/null; then
    log_step "Installing mise version manager..."
    curl https://mise.run | sh
    # Add to path for current session
    export PATH="$HOME/.local/bin:$PATH"
    require_command "mise"
    log_info "mise $(mise --version) installed"
else
    log_info "mise already installed: $(mise --version)"
fi

# -------------------------------------------
# fd symlink (apt package is fd-find, command is fdfind)
# -------------------------------------------

if command -v fdfind &> /dev/null && ! command -v fd &> /dev/null; then
    log_step "Creating fd symlink..."
    sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
    log_info "fd symlink created"
fi

# -------------------------------------------
# Rclone (cloud storage sync)
# -------------------------------------------

if ! command -v rclone &> /dev/null; then
    log_step "Installing rclone..."
    curl -sS https://rclone.org/install.sh | sudo bash
    require_command "rclone"
    log_info "rclone $(rclone version | head -1) installed"
else
    log_info "rclone already installed: $(rclone version | head -1)"
fi

# -------------------------------------------
# Enable services
# -------------------------------------------

sudo systemctl enable ssh
sudo systemctl start ssh

log_info "Package installation complete"
