#!/bin/bash
# ===========================================
# Homelab Setup Orchestrator
# ===========================================
# This script runs all setup steps in order.
# It's called by setup.sh after cloning the repository.
#
# Usage: ./scripts/setup/--init.sh

set -e

# -------------------------------------------
# Determine paths
# -------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# -------------------------------------------
# Load config and TUI
# -------------------------------------------

source "$PROJECT_DIR/scripts/lib/config.sh"
source "$PROJECT_DIR/scripts/lib/tui.sh"

# -------------------------------------------
# Check requirements
# -------------------------------------------

check_requirements() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run this script as root. Run as regular user with sudo access."
        exit 1
    fi

    if ! has_command sudo; then
        log_error "sudo is not installed"
        exit 1
    fi

    log_info "Running as user: $USER"
    log_info "Home directory: $HOME"

    # Request sudo password upfront
    log_step "Requesting sudo access..."
    sudo -v

    # Keep sudo alive
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    log_info "sudo access granted"
}

# -------------------------------------------
# Main
# -------------------------------------------

main() {
    clear
    print_box "HOMELAB SETUP"
    echo "      github.com/${GITHUB_USER}/${GITHUB_REPO}"
    echo ""

    check_requirements

    # Run all numbered scripts in order
    for script in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
        if [[ -f "$script" ]]; then
            bash "$script"
        fi
    done

    print_footer "Setup complete!"
}

main "$@"
