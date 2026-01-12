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

    # Ensure USER is set (not always set in Docker)
    export USER="${USER:-$(whoami)}"

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
# Setup SSH key for passwordless access
# -------------------------------------------

setup_client_ssh_key() {
    print_header "SSH Key Setup (passwordless login)"

    echo -e "Чтобы входить на сервер без пароля, добавьте свой SSH-ключ."
    echo ""
    echo -e "${CYAN}─── Как получить ключ на вашем компьютере ───${NC}"
    echo ""
    echo -e "  ${BOLD}macOS/Linux:${NC}"
    echo -e "    cat ~/.ssh/id_ed25519.pub"
    echo ""
    echo -e "  ${BOLD}Windows (PowerShell):${NC}"
    echo -e "    type \$env:USERPROFILE\\.ssh\\id_ed25519.pub"
    echo ""
    echo -e "  ${BOLD}Если ключа нет — создайте:${NC}"
    echo -e "    ssh-keygen -t ed25519"
    echo ""
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    echo ""

    # Skip in test mode
    if [[ "${TEST_MODE:-0}" == "1" ]]; then
        log_info "[TEST] Skipping SSH key setup"
        return 0
    fi

    if ! confirm "Добавить SSH-ключ для входа без пароля?" "y"; then
        log_info "Пропускаем настройку SSH-ключа"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}Вставьте ваш публичный ключ (одной строкой, начинается с ssh-):${NC}"
    read -r ssh_key

    # Validate key format
    if [[ ! "$ssh_key" =~ ^ssh-(ed25519|rsa|ecdsa) ]]; then
        log_error "Неверный формат ключа. Ключ должен начинаться с ssh-ed25519, ssh-rsa или ssh-ecdsa"
        return 1
    fi

    # Setup authorized_keys
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # Check if key already exists
    if [[ -f "$HOME/.ssh/authorized_keys" ]] && grep -qF "$ssh_key" "$HOME/.ssh/authorized_keys"; then
        log_info "Этот ключ уже добавлен"
    else
        echo "$ssh_key" >> "$HOME/.ssh/authorized_keys"
        chmod 600 "$HOME/.ssh/authorized_keys"
        log_info "SSH-ключ добавлен в authorized_keys"
    fi

    echo ""
    log_info "Теперь вы можете входить без пароля: ssh $USER@$(hostname)"
    echo ""
}

# -------------------------------------------
# Main
# -------------------------------------------

main() {
    clear
    print_box "HOMELAB SETUP"
    echo "github.com/${GITHUB_USER}/${GITHUB_REPO}"
    echo ""

    check_requirements
    setup_client_ssh_key

    # Run all numbered scripts in order
    for script in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
        if [[ -f "$script" ]]; then
            bash "$script"
        fi
    done

    # Final verification (skip in TEST_MODE - Docker can't verify all checks)
    if [[ "${TEST_MODE:-0}" != "1" ]]; then
        echo ""
        log_step "Running final healthcheck..."
        if bash "$PROJECT_DIR/scripts/healthcheck.sh"; then
            print_footer "Setup complete!"
        else
            log_error "Setup completed with errors. Review healthcheck output above."
            exit 1
        fi
    else
        log_info "[TEST] Skipping healthcheck in test mode"
        print_footer "Setup complete!"
    fi
}

main "$@"
