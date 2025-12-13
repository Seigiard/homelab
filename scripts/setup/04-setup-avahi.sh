#!/bin/bash
# ===========================================
# Step 04: Configure Avahi (mDNS)
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 5/9: Configuring Avahi (mDNS)"

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

# Restart avahi
sudo systemctl restart avahi-daemon
sudo systemctl enable avahi-daemon

log_info "Avahi configured: ${HOSTNAME}.local"
