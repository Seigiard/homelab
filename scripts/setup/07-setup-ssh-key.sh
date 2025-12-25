#!/bin/bash
# ===========================================
# Step 07: Setup SSH Key for GitHub
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 8/9: Setting up SSH key for GitHub"

SSH_KEY="$HOME/.ssh/id_ed25519"

if [[ -f "$SSH_KEY" ]]; then
    log_info "SSH key already exists: $SSH_KEY"
else
    log_step "Generating new SSH key..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$SSH_KEY" -N ""

    # Verify key was created
    if [[ -f "$SSH_KEY" && -f "${SSH_KEY}.pub" ]]; then
        log_info "SSH key generated"
    else
        log_error "SSH key generation failed"
        exit 1
    fi
fi

# Start ssh-agent
eval "$(ssh-agent -s)" > /dev/null
ssh-add "$SSH_KEY" 2>/dev/null

# Always show key and instructions
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  ВАЖНО: Добавьте этот SSH-ключ в GitHub перед продолжением${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  1. Скопируйте ключ ниже"
echo -e "  2. Откройте: ${CYAN}https://github.com/settings/ssh/new${NC}"
echo -e "  3. Вставьте ключ и нажмите 'Add SSH key'"
echo ""
echo -e "${CYAN}─── Ваш публичный ключ ───${NC}"
cat "${SSH_KEY}.pub"
echo -e "${CYAN}──────────────────────────${NC}"
echo ""

press_enter

# Skip GitHub operations in test mode
if [[ "${TEST_MODE:-0}" == "1" ]]; then
    log_info "[TEST] Skipping GitHub connection test"
else
    # Add GitHub to known_hosts (prevents interactive prompt)
    log_step "Adding GitHub to known_hosts..."
    ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null

    # Test connection
    log_step "Testing GitHub connection..."
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        log_info "GitHub SSH connection successful"
    else
        log_warn "Could not verify GitHub connection (this might be ok)"
    fi

    # Switch remote to SSH (only if repo exists)
    if [[ -d "$INSTALL_PATH/.git" ]]; then
        log_step "Switching remote to SSH..."
        cd "$INSTALL_PATH"
        git remote set-url origin "git@github.com:${GITHUB_USER}/${GITHUB_REPO}.git"
        log_info "Remote switched to SSH"
    fi
fi
