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

# -------------------------------------------
# Network (static IP)
# -------------------------------------------

export NET_INTERFACE="eno1"
export NET_IP="192.168.1.41/24"
export NET_GATEWAY="192.168.1.1"
export NET_DNS_PRIMARY="127.0.0.1"
export NET_DNS_FALLBACK="1.1.1.1"

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
