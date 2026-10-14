#!/bin/bash
# ===========================================
# Step 13: Install the container drift watch timer
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$PROJECT_DIR/scripts/lib/tui.sh"

print_header "Step 13: Installing the container drift watch"

log_step "Installing systemd units"
sed "s|__PROJECT_DIR__|$PROJECT_DIR|g" "$PROJECT_DIR/scripts/systemd/container-drift-watch.service" \
    | sudo tee /etc/systemd/system/container-drift-watch.service > /dev/null
sudo install -m 644 "$PROJECT_DIR/scripts/systemd/container-drift-watch.timer" \
    /etc/systemd/system/container-drift-watch.timer

log_step "Enabling the timer"
sudo systemctl daemon-reload
sudo systemctl enable --now container-drift-watch.timer

log_info "Container drift watch active"
log_info "Follow it with: journalctl -t container-drift-watch -f"
