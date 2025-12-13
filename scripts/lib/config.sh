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
