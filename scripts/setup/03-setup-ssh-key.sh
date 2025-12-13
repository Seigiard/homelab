#!/bin/bash
# ===========================================
# Step 03: Setup SSH Key for GitHub
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 4/9: Setting up SSH key for GitHub"

SSH_KEY="$HOME/.ssh/id_ed25519"

if [[ -f "$SSH_KEY" ]]; then
    log_warn "SSH key already exists: $SSH_KEY"
else
    log_step "Generating new SSH key..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$SSH_KEY" -N ""
    log_info "SSH key generated"
fi

# Start ssh-agent
eval "$(ssh-agent -s)" > /dev/null
ssh-add "$SSH_KEY" 2>/dev/null

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Add this SSH key to GitHub:${NC}"
echo -e "${YELLOW}  https://github.com/settings/ssh/new${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
echo ""
cat "${SSH_KEY}.pub"
echo ""

press_enter

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
