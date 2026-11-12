#!/bin/bash
# ===========================================
# Step 04: Configure Avahi (mDNS)
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 5/11: Configuring Avahi (mDNS)"

# Set hostname
log_step "Setting hostname to: $HOSTNAME"
sudo hostnamectl set-hostname "$HOSTNAME"

# Verify hostname (skip in test mode - mock doesn't change real hostname)
if [[ "${TEST_MODE:-0}" == "1" ]]; then
    log_info "[TEST] Hostname would be set to: $HOSTNAME"
elif [[ "$(hostname)" == "$HOSTNAME" ]]; then
    log_info "Hostname set: $HOSTNAME"
else
    log_error "Failed to set hostname"
    exit 1
fi

# Configure avahi
sudo tee /etc/avahi/avahi-daemon.conf > /dev/null << EOF
[server]
host-name=$HOSTNAME
domain-name=local
use-ipv4=yes
use-ipv6=yes

[publish]
publish-addresses=yes
publish-hinfo=yes
publish-workstation=yes
publish-domain=yes

[reflector]

[rlimits]
EOF

# Service announcements (Time Machine shares of the samba container)
log_step "Installing Avahi service files"
for service_file in "$PROJECT_DIR"/scripts/avahi/*.service; do
    sudo install -m 644 "$service_file" /etc/avahi/services/
    log_info "Installed: /etc/avahi/services/$(basename "$service_file")"
done

# Restart avahi
sudo systemctl restart avahi-daemon
sudo systemctl enable avahi-daemon

log_info "Avahi configured: ${HOSTNAME}.local"
