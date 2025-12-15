#!/bin/bash
# ===========================================
# Step 08: Show Summary
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 9/9: Setup Complete!"

log_info "Installed packages:"
echo "      APT:   ${APT_PACKAGES[*]}"
echo "      Snap:  ${SNAP_PACKAGES[*]}"
echo "      Cargo: ${CARGO_PACKAGES[*]}"
echo ""

log_info "Configuration:"
echo "      Hostname: ${HOSTNAME}.local"
echo "      SSH key:  ~/.ssh/id_ed25519"
echo "      Homelab:  $INSTALL_PATH (~/homelab)"
echo "      Shell:    zsh"
echo ""

log_warn "Next steps:"
echo "      1. Log out and back in (for zsh)"
echo "      2. Edit $INSTALL_PATH/.env if needed"
echo "      3. Run: cd ~/homelab && ./scripts/deploy.sh"
