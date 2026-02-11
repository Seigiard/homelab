#!/bin/bash
# ===========================================
# Step 00: Update System
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 1/9: Updating system"

log_step "Setting timezone to ${TIMEZONE}..."
sudo timedatectl set-timezone "$TIMEZONE"

log_step "Enabling NTP sync..."
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

log_step "Running apt update..."
sudo apt update

log_step "Running apt upgrade..."
sudo apt upgrade -y

log_info "System updated"
