#!/bin/bash
# ===========================================
# Step 10: Configure Tailscale (mesh VPN)
# ===========================================
# Tailscale работает на хосте (как NUT), не в Docker.
# Аутентификация интерактивная: при первом запуске печатает URL для входа.
# DNS: accept-dns=false, чтобы не сломать split-horizon AdGuard (см. config.sh).
# Роль — SSH + mesh. Subnet-router НЕ используем: анонс собственного IP сервера
# самореферентен и ломает локальный доступ LAN-клиентов (см. ENVIRONMENT.md → Грабли).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 11/11: Configuring Tailscale (mesh VPN)"

# Тестовый прогон (--init.sh с TEST_MODE=1) не должен ставить Tailscale и уходить
# в интерактивный login — пропускаем, как делают шаги 04/06/07.
if [[ "${TEST_MODE:-0}" == "1" ]]; then
    log_info "[TEST] Skipping Tailscale setup"
    exit 0
fi

# --- Install (idempotent) ---
if has_command tailscale; then
    log_info "Tailscale already installed: $(tailscale version | head -1)"
else
    log_step "Installing Tailscale (official apt repo)..."
    # Скачиваем отдельным шагом: при curl|sh статус пайпа = код sh, и оборванная
    # загрузка прошла бы как успех, всплыв позже как «tailscale: command not found».
    TS_INSTALLER="$(mktemp)"
    curl -fsSL --retry 3 --max-time 60 https://tailscale.com/install.sh -o "$TS_INSTALLER"
    sh "$TS_INSTALLER"
    rm -f "$TS_INSTALLER"
fi

# --- IP forwarding (нужно только для exit node / subnet router) ---
# Делаем ДО login: ранний выход login не должен оставить persistent sysctl.
SYSCTL_FILE="/etc/sysctl.d/99-tailscale.conf"
if [[ "$TS_ADVERTISE_EXIT_NODE" == "true" || -n "$TS_ADVERTISE_ROUTES" ]]; then
    log_step "Enabling persistent IP forwarding (exit node / subnet router)..."
    sudo tee "$SYSCTL_FILE" > /dev/null << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
    sudo sysctl -p "$SYSCTL_FILE" > /dev/null
elif [[ -f "$SYSCTL_FILE" ]]; then
    log_step "Removing stale Tailscale IP-forwarding config (no routes/exit-node)..."
    sudo rm -f "$SYSCTL_FILE"
    # Намеренно НЕ выставляем ip_forward=0 в рантайме: его использует Docker.
fi

# --- Bring up + login (interactive, only when not already running) ---
ts_state() { tailscale status --json 2>/dev/null | jq -r '.BackendState // "NoState"'; }

if [[ "$(ts_state)" != "Running" ]]; then
    log_step "Logging in to Tailscale (откроется URL для входа в браузере)..."
    # Полный набор non-default префов передаём и в `up`: на уже сконфигурированной,
    # но остановленной ноде `up` может отвергнуть неполный набор флагов.
    # Login необязателен — отказ/Ctrl-C не должен валить весь установщик (шаг последний).
    if ! sudo tailscale up \
        --hostname="$TS_HOSTNAME" \
        --ssh="$TS_SSH" \
        --accept-dns="$TS_ACCEPT_DNS" \
        --advertise-routes="$TS_ADVERTISE_ROUTES" \
        --advertise-exit-node="$TS_ADVERTISE_EXIT_NODE"; then
        log_warn "Tailscale login пропущен/не удался — перезапусти шаг позже: $0"
        exit 0
    fi
else
    log_info "Tailscale already up and running"
fi

# --- Enforce desired prefs (idempotent, surgical: не трогает прочие настройки) ---
log_step "Applying preferences (ssh=$TS_SSH, accept-dns=$TS_ACCEPT_DNS, exit-node=$TS_ADVERTISE_EXIT_NODE, routes=${TS_ADVERTISE_ROUTES:-none})..."
sudo tailscale set \
    --hostname="$TS_HOSTNAME" \
    --ssh="$TS_SSH" \
    --accept-dns="$TS_ACCEPT_DNS" \
    --advertise-exit-node="$TS_ADVERTISE_EXIT_NODE" \
    --advertise-routes="$TS_ADVERTISE_ROUTES"

# --- Verify prefs landed (machine-checkable) ---
PREFS="$(sudo tailscale debug prefs 2>/dev/null)"
if grep -q "\"RunSSH\": ${TS_SSH}," <<< "$PREFS" && grep -q "\"CorpDNS\": ${TS_ACCEPT_DNS}," <<< "$PREFS"; then
    log_info "Prefs OK: RunSSH=${TS_SSH}, CorpDNS=${TS_ACCEPT_DNS}"
else
    log_warn "Prefs check failed — проверь: sudo tailscale debug prefs"
fi

TS_IP="$(tailscale ip -4 2>/dev/null | head -1)"

log_info "Tailscale configured"
[[ -n "$TS_IP" ]] && log_info "Tailnet IP: ${TS_IP}"
log_info "SSH по tailnet: ssh ${USER}@${TS_HOSTNAME}"
log_info "Verify: tailscale status"
