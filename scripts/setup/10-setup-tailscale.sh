#!/bin/bash
# ===========================================
# Step 10: Configure Tailscale (mesh VPN)
# ===========================================
# Tailscale работает на хосте (как NUT), не в Docker.
# Аутентификация интерактивная: при первом запуске печатает URL для входа.
# DNS: accept-dns=false, чтобы не сломать split-horizon AdGuard (см. config.sh).

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

# --- IP forwarding (нужно для exit node и subnet router) ---
SYSCTL_FILE="/etc/sysctl.d/99-tailscale.conf"
if [[ "$TS_ADVERTISE_EXIT_NODE" == "true" || -n "$TS_ADVERTISE_ROUTES" ]]; then
    log_step "Enabling persistent IP forwarding (exit node / subnet router)..."
    sudo tee "$SYSCTL_FILE" > /dev/null << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
    sudo sysctl -p "$SYSCTL_FILE" > /dev/null
elif [[ -f "$SYSCTL_FILE" ]]; then
    log_step "Removing Tailscale IP-forwarding config (no routes/exit-node advertised)..."
    sudo rm -f "$SYSCTL_FILE"
    # Намеренно НЕ выставляем ip_forward=0 в рантайме: его использует Docker.
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
log_info "Verify: tailscale status"

# --- Manual follow-up (не воспроизводится скриптом) ---
print_header "Tailscale: ручные шаги (нужны один раз)"

echo "SSH по tailnet (работает сразу):"
echo "  ssh ${USER}@${TS_HOSTNAME}"

if [[ -n "$TS_ADVERTISE_ROUTES" ]]; then
    echo ""
    echo "Чтобы *.1218217.xyz ходили напрямую домой при включённом Tailscale:"
    echo ""
    echo "1) Админка https://login.tailscale.com/admin :"
    echo "   • Machines → ${TS_HOSTNAME} → Edit route settings → одобрить ${TS_ADVERTISE_ROUTES}"
    echo "   • DNS → Nameservers → Custom: домен 1218217.xyz → ${TS_IP:-<tailnet-IP сервера>} (домашний AdGuard, split-DNS)"
    echo "     Global nameserver НЕ менять на AdGuard — оставить облачный (NextDNS),"
    echo "     иначе весь DNS роуминг-устройств зависит от аптайма дома."
    echo ""
    echo "2) Клиентские устройства:"
    echo "   • macOS:   sudo tailscale set --accept-routes   (+ включить Use Tailscale DNS)"
    echo "   • Android: Tailscale → Use Tailscale DNS = ON;"
    echo "              системные Настройки → Private DNS → Off (конфликтует с MagicDNS)"
    echo "   • iOS:     включить subnet routes + Use Tailscale DNS в приложении Tailscale"
    echo ""
    echo "Проверка вне дома (не dig — он на Android врёт):"
    echo "   curl -s https://dns.1218217.xyz -o /dev/null -w '%{remote_ip}\\n'   → ${TS_ADVERTISE_ROUTES%/*}"
fi
