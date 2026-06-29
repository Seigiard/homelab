#!/bin/bash
# ===========================================
# Step 11: Fan sensors (AOOSTAR WTR Pro — Super-I/O IT8613E)
# ===========================================
# Плата AOOSTAR использует Super-I/O ITE IT8613E, который штатное ядро Ubuntu не
# поддерживает (chip ID 0x8613 нет в in-kernel it87) — обороты вентиляторов не видны.
# Ставим out-of-tree DKMS-драйвер frankcrawford/it87 (пиннинг коммита) ТОЛЬКО для
# ЧТЕНИЯ оборотов. Управление вентилятором оставлено EC/BIOS — manual PWM не трогаем
# (если управляющий процесс упадёт, обороты застынут). См. ENVIRONMENT.md.
#
# Hardware-guarded: если IT8613E не найден — тихо выходит (no-op на другом железе).
# Переменные (IT87_*) — в config.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Fan sensors (Super-I/O ${IT87_CHIP})"

if [[ "${TEST_MODE:-0}" == "1" ]]; then
    log_info "[TEST] Skipping fan-sensors setup"
    exit 0
fi

# --- Hardware guard: только при наличии IT8613E ---
# force_id насильно привязывает драйвер к 0x8613 независимо от реального чипа,
# поэтому на чужом железе грузить it87 нельзя — сначала детект.
if ! has_command sensors-detect; then
    log_step "Installing lm-sensors..."
    sudo apt install -y lm-sensors
fi

if ! sudo sensors-detect --auto 2>/dev/null | grep -q "$IT87_CHIP"; then
    log_info "Super-I/O ${IT87_CHIP} не найден — пропускаю (не-AOOSTAR железо)"
    exit 0
fi
log_info "Найден Super-I/O ${IT87_CHIP}"

# --- DKMS-драйвер it87 (out-of-tree, поддерживает IT8613E; idempotent) ---
if dkms status 2>/dev/null | grep -q '^it87'; then
    log_info "Драйвер it87 (DKMS) уже установлен"
else
    log_step "Installing build deps (dkms, kernel headers)..."
    sudo apt install -y dkms build-essential "linux-headers-$(uname -r)"

    log_step "Building it87 driver (frankcrawford/it87 @ ${IT87_COMMIT:0:12})..."
    BUILD_DIR="$(mktemp -d)"
    git clone "$IT87_REPO" "$BUILD_DIR"
    git -C "$BUILD_DIR" checkout -q "$IT87_COMMIT"
    sudo "$BUILD_DIR/dkms-install.sh"
    rm -rf "$BUILD_DIR"
fi

# --- Persist module autoload + force_id (видимость после ребута) ---
log_step "Configuring autoload (force_id=${IT87_FORCE_ID})..."
echo "options it87 ${IT87_MODOPTS}" | sudo tee /etc/modprobe.d/it87.conf > /dev/null
echo "it87" | sudo tee /etc/modules-load.d/it87.conf > /dev/null

# --- Load now (idempotent) ---
if ! lsmod | grep -q '^it87'; then
    log_step "Loading it87 module..."
    sudo modprobe it87 ${IT87_MODOPTS} 2>/dev/null || log_warn "modprobe it87 не удался — проверь: sudo dmesg | grep it87"
fi

# --- sensors.d: скрыть мусорные показания generic-драйвера ---
# Полезны только обороты (fan2/fan3) и температуры (temp2/temp3). Вольтажи и
# intrusion0 — некалиброванный шум с ложными ALARM. Остаются две строки
# temp3_min/max I/O error (квирк чипа): они в stderr, на stdout вывод чистый.
log_step "Writing sensors.d filter..."
sudo tee /etc/sensors.d/aoostar-it8613.conf > /dev/null << 'EOF'
# AOOSTAR WTR Pro — IT8613E (generic it87): прячем мусорные показания.
# Полезны только обороты вентиляторов (fan2/fan3) и температуры (temp2/temp3).
chip "it8613-isa-*"
    ignore in0
    ignore in1
    ignore in2
    ignore in3
    ignore in4
    ignore in5
    ignore in6
    ignore in7
    ignore in8
    ignore in9
    ignore in10
    ignore cpu0_vid
    ignore fan1
    ignore fan4
    ignore fan5
    ignore temp1
    ignore intrusion0
EOF

# --- Verify ---
if sensors 2>/dev/null | grep -q '^fan[0-9]'; then
    log_info "Вентиляторы видны (управление оставлено EC/BIOS):"
    sensors 2>/dev/null | grep -E '^(fan|temp)[0-9]' | sed 's/^/    /'
else
    log_warn "Обороты вентилятора не видны — проверь: sudo dmesg | grep it87"
fi
