#!/bin/bash
# ===========================================
# Step 04: Configure Git
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 5/9: Configuring Git"

git config --global user.name "$GITHUB_USER"
git config --global user.email "$GITHUB_EMAIL"
git config --global init.defaultBranch main
git config --global core.editor micro
git config --global pull.rebase false

log_info "Git configured for $GITHUB_USER <$GITHUB_EMAIL>"
