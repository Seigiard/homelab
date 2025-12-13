#!/bin/bash
# ===========================================
# Step 07: Run Bootstrap (Docker, folders, permissions)
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 8/9: Running bootstrap.sh"

BOOTSTRAP="$INSTALL_PATH/scripts/bootstrap.sh"

if [[ ! -f "$BOOTSTRAP" ]]; then
    log_error "Bootstrap script not found: $BOOTSTRAP"
    exit 1
fi

# Check for .env file
if [[ ! -f "$INSTALL_PATH/.env" ]]; then
    if [[ -f "$INSTALL_PATH/.env.example" ]]; then
        log_step "Creating .env from .env.example..."
        cp "$INSTALL_PATH/.env.example" "$INSTALL_PATH/.env"
        log_warn "Please edit $INSTALL_PATH/.env with your settings"
    else
        log_error ".env file required. Create it from .env.example"
        exit 1
    fi
fi

log_step "Running bootstrap..."
sudo TEST_MODE="${TEST_MODE:-0}" "$BOOTSTRAP"

log_info "Bootstrap completed"
