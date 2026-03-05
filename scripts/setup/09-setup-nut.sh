#!/bin/bash
# ===========================================
# Step 09: Configure NUT (Network UPS Tools)
# ===========================================
# UPS: Eaton Ellipse ECO 900 USB
# NUT runs on the host for reliable shutdown.
# PeaNUT (Docker) connects to host NUT for web UI.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 10/10: Configuring NUT (UPS monitoring)"

NUT_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)

log_step "Setting USB permissions for NUT (udev rule)"
sudo tee /etc/udev/rules.d/99-nut-ups.rules > /dev/null << 'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="0463", MODE="0660", GROUP="nut"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger

log_step "Writing /etc/nut/nut.conf"
sudo tee /etc/nut/nut.conf > /dev/null << 'EOF'
MODE=standalone
EOF

log_step "Writing /etc/nut/ups.conf"
sudo tee /etc/nut/ups.conf > /dev/null << 'EOF'
[eaton]
  driver = usbhid-ups
  port = auto
  desc = "Eaton Ellipse ECO 900"
EOF

log_step "Writing /etc/nut/upsd.conf"
sudo tee /etc/nut/upsd.conf > /dev/null << 'EOF'
LISTEN 0.0.0.0 3493
EOF

log_step "Writing /etc/nut/upsd.users"
sudo tee /etc/nut/upsd.users > /dev/null << EOF
[upsmon]
  password = ${NUT_PASSWORD}
  upsmon master
  actions = SET
  instcmds = ALL
EOF

log_step "Writing /etc/nut/upsmon.conf"
sudo tee /etc/nut/upsmon.conf > /dev/null << EOF
MONITOR eaton@localhost 1 upsmon ${NUT_PASSWORD} master
SHUTDOWNCMD "/sbin/shutdown -h +0"
POWERDOWNFLAG /etc/killpower
FINALDELAY 5
EOF

sudo chmod 640 /etc/nut/upsd.users /etc/nut/upsmon.conf
sudo chown root:nut /etc/nut/upsd.users /etc/nut/upsmon.conf

log_step "Opening firewall for Docker → NUT"
sudo ufw allow from 172.16.0.0/12 to any port 3493 proto tcp comment "NUT from Docker" 2>/dev/null || true

log_step "Enabling NUT services"
sudo systemctl restart nut-driver 2>/dev/null || true
sudo systemctl enable --now nut-server
sudo systemctl enable --now nut-monitor

APPDATA="${INSTALL_PATH}/appdata"
PEANUT_CONFIG_DIR="${APPDATA}/peanut/config"

log_step "Creating PeaNUT settings.yml"
mkdir -p "${PEANUT_CONFIG_DIR}"
cat > "${PEANUT_CONFIG_DIR}/settings.yml" << EOF
NUT_SERVERS:
  - HOST: host.docker.internal
    PORT: 3493
    USERNAME: upsmon
    PASSWORD: ${NUT_PASSWORD}
EOF
chmod 777 "${PEANUT_CONFIG_DIR}"

log_step "Disabling UPS beeper and setting shutdown delay"
sudo upscmd -u upsmon -p "${NUT_PASSWORD}" eaton beeper.disable 2>/dev/null || true
sudo upsrw -s ups.delay.shutdown=120 -u upsmon -p "${NUT_PASSWORD}" eaton 2>/dev/null || true

log_info "NUT configured for Eaton Ellipse ECO 900"
log_info "Password saved in /etc/nut/upsd.users"
log_info "PeaNUT config: ${PEANUT_CONFIG_DIR}/settings.yml"
log_info "Verify: sudo upsc eaton@localhost"
