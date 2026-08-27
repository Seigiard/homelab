#!/bin/bash
# ===========================================
# Step 12: Install the AdGuard watchdog timer
# ===========================================
# adguard serves DNS for the host itself, so losing that container takes the
# whole machine offline by name. The timer notices within a minute and
# redeploys it. See scripts/adguard-watchdog.sh for the reasoning.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$PROJECT_DIR/scripts/lib/tui.sh"

print_header "Step 12: Installing the AdGuard watchdog"

log_step "Installing systemd units"
sed "s|__PROJECT_DIR__|$PROJECT_DIR|g" "$PROJECT_DIR/scripts/systemd/adguard-watchdog.service" \
    | sudo tee /etc/systemd/system/adguard-watchdog.service > /dev/null
sudo install -m 644 "$PROJECT_DIR/scripts/systemd/adguard-watchdog.timer" \
    /etc/systemd/system/adguard-watchdog.timer

log_step "Enabling the timer"
sudo systemctl daemon-reload
sudo systemctl enable --now adguard-watchdog.timer

log_info "Watchdog active"
log_info "Follow it with: journalctl -t adguard-watchdog -f"
log_info "Pause for maintenance: sudo touch /run/adguard-watchdog.disabled"
