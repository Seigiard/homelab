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

    # Verify installation
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log_info "Oh-My-Zsh installed"
    else
        log_error "Oh-My-Zsh installation failed"
        exit 1
    fi
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

# Verify plugins
if [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" && -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    log_info "Plugins installed"
else
    log_error "Plugin installation failed"
    exit 1
fi

# Change default shell (check via /etc/passwd, not $SHELL)
current_shell=$(get_user_shell)
if [[ "$current_shell" != *"zsh"* ]]; then
    log_step "Changing default shell to zsh..."
    sudo chsh -s "$(which zsh)" "$USER"

    # Verify shell changed
    new_shell=$(get_user_shell)
    if [[ "$new_shell" == *"zsh"* ]]; then
        log_info "Default shell changed to zsh"
    else
        log_error "Failed to change shell to zsh"
        exit 1
    fi
else
    log_info "Zsh is already default shell"
fi

log_info "Zsh setup complete"
