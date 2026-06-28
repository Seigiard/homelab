#!/bin/bash
# ===========================================
# Homelab Configuration
# ===========================================
# Shared variables for all setup scripts.
# Source this file before tui.sh:
#   source "$(dirname "$0")/../lib/config.sh"
#   source "$(dirname "$0")/../lib/tui.sh"

# -------------------------------------------
# GitHub
# -------------------------------------------

export GITHUB_USER="seigiard"
export GITHUB_EMAIL="seigiard@gmail.com"
export GITHUB_REPO="homelab"

# -------------------------------------------
# Paths
# -------------------------------------------

export INSTALL_PATH="/opt/homelab"

# -------------------------------------------
# Server
# -------------------------------------------

export HOSTNAME="home"
export TIMEZONE="Europe/Bratislava"

# -------------------------------------------
# Network (static IP)
# -------------------------------------------

# Сетевой интерфейс задаётся glob-паттерном для netplan `match`, а не именем
# устройства. Не зависит от железа (eno1, enpXsY и т.д.) — систему можно
# перенести на другой NIC без правки конфигурации сети. nic-tuning резолвит
# активный интерфейс в рантайме (см. bootstrap.sh), тоже без хардкода имени.
export NET_INTERFACE_MATCH="en*"
export NET_IP="192.168.1.41/24"
export NET_GATEWAY="192.168.1.1"
# Единственный основной DNS хоста — локальный AdGuard. НЕ добавлять второй адрес
# в nameservers: systemd-resolved ротирует список и уводит запросы мимо AdGuard
# (ломается split-horizon). Резерв задаётся отдельно через FallbackDNS (см. ниже).
export NET_DNS_PRIMARY="127.0.0.1"
# Строгий fallback в systemd-resolved — используется только когда AdGuard недоступен
export NET_DNS_FALLBACK="1.1.1.1 1.0.0.1"

# -------------------------------------------
# Tailscale (host-сервис — как NUT, не Docker)
# -------------------------------------------

# Имя ноды в tailnet. По умолчанию = system hostname.
export TS_HOSTNAME="${HOSTNAME}"

# accept-dns=false — НЕ позволяем Tailscale переписывать /etc/resolv.conf.
# Иначе host начинает резолвить через MagicDNS (100.100.100.100) в обход
# AdGuard, и ломается split-horizon для *.1218217.xyz (см. NET_DNS_PRIMARY).
# Серверу MagicDNS не нужен — резолв остаётся через локальный AdGuard.
export TS_ACCEPT_DNS="false"

# Tailscale SSH — доступ к серверу по tailnet без проброса портов и SSH-ключей.
export TS_SSH="true"

# Exit node — гнать интернет-трафик клиентов через дом. Выключено.
# При true шаг настраивает IP forwarding (/etc/sysctl.d/99-tailscale.conf);
# дополнительно нужно одобрить exit-node в админке Tailscale (вручную).
export TS_ADVERTISE_EXIT_NODE="false"

# Subnet router — какие маршруты LAN анонсировать в tailnet. Нужно, чтобы
# устройство «снаружи + Tailscale» дотягивалось до домашнего сервера напрямую
# (в паре со split-DNS 1218217.xyz → tailnet-IP сервера в админке tailnet).
# /32 (только сервер) безопаснее /24: нет конфликта с чужой сетью 192.168.1.0/24.
# Выводится из NET_IP — один источник правды для адреса сервера.
# Пусто = не анонсировать. Анонс включает IP forwarding и требует approval в админке.
export TS_ADVERTISE_ROUTES="${NET_IP%/*}/32"

# -------------------------------------------
# Packages
# -------------------------------------------

# APT packages to install
APT_PACKAGES=(
    # Essential
    curl
    wget
    build-essential
    # Editors
    micro
    # Terminal tools
    btop       # htop replacement with graphs
    mc
    tree
    ncdu
    jq
    fd-find    # fast find alternative
    ripgrep    # fast grep alternative
    fzf        # fuzzy finder
    # Media
    ffmpeg
    mediainfo
    imagemagick
    chafa      # terminal image viewer (fallback for non-Kitty terminals)
    # UPS
    nut
    # Network
    ethtool
    openssh-server
    avahi-daemon
    avahi-utils
    # Shell
    zsh
)

# Cargo packages (cross-platform CLI tools)
CARGO_PACKAGES=(
    eza        # ls replacement with icons/colors
    bat        # cat with syntax highlighting
    procs      # ps replacement with tree view
    du-dust    # du replacement with visual tree
    duf        # df replacement with nice table
    rgrc       # colorizes terminal output
    zoxide     # smarter cd command
)
# Note: yazi installed separately (requires yazi-build)

# -------------------------------------------
# Environment fixes (Docker compatibility)
# -------------------------------------------

# USER may not be set in Docker
export USER="${USER:-$(whoami)}"
