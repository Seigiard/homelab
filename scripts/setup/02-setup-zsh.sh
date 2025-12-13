#!/bin/bash
# ===========================================
# Step 02: Setup Zsh + Oh-My-Zsh
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 3/9: Setting up Zsh + Oh-My-Zsh"

if [[ -d "$HOME/.oh-my-zsh" ]]; then
    log_warn "Oh-My-Zsh already installed, skipping"
else
    log_step "Installing Oh-My-Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    log_info "Oh-My-Zsh installed"
fi

# Install plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    log_step "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    log_step "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# Change default shell
if [[ "$SHELL" != *"zsh"* ]]; then
    log_step "Changing default shell to zsh..."
    sudo chsh -s "$(which zsh)" "$USER"
    log_info "Default shell changed to zsh"
else
    log_info "Zsh is already default shell"
fi

log_info "Zsh setup complete"
