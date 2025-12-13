#!/bin/bash
# ===========================================
# Step 05: Configure Avahi (mDNS)
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 6/9: Configuring Avahi (mDNS)"

# Set hostname
log_step "Setting hostname to: $HOSTNAME"
sudo hostnamectl set-hostname "$HOSTNAME"

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
