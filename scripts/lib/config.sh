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
    htop
    mc
    tree
    ncdu
    jq
    # Network
    openssh-server
    avahi-daemon
    avahi-utils
    # Shell
    zsh
)

# Snap packages
SNAP_PACKAGES=(zellij)

# Cargo packages
CARGO_PACKAGES=(rgrc)

# -------------------------------------------
# Environment fixes (Docker compatibility)
# -------------------------------------------

# USER may not be set in Docker
export USER="${USER:-$(whoami)}"
