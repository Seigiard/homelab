#!/bin/bash
# ===========================================
# Homelab Healthcheck
# ===========================================
# Проверяет состояние системы после установки.
# Usage: ./scripts/healthcheck.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/tui.sh"

# -------------------------------------------
# Counters
# -------------------------------------------

PASSED=0
FAILED=0

check_pass() {
    log_info "$1"
    ((PASSED++))
}

check_fail() {
    log_error "$1"
    ((FAILED++))
}

# -------------------------------------------
# Checks
# -------------------------------------------

print_box "HEALTHCHECK"

# --- Packages ---
print_header "Packages"

packages=(git curl wget zsh jq htop mc tree ncdu micro)
for pkg in "${packages[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        check_pass "$pkg"
    else
        check_fail "$pkg not installed"
    fi
done

# Zellij (snap)
if command -v zellij &>/dev/null; then
    check_pass "zellij"
else
    check_fail "zellij not installed"
fi

# --- Shell ---
print_header "Shell"

current_shell=$(get_user_shell)
if [[ "$current_shell" == *"zsh"* ]]; then
    check_pass "Default shell: zsh"
else
    check_fail "Default shell is not zsh: $current_shell"
fi

if [[ -d "$HOME/.oh-my-zsh" ]]; then
    check_pass "Oh-My-Zsh installed"
else
    check_fail "Oh-My-Zsh not found"
fi

# --- SSH ---
print_header "SSH"

SSH_KEY="$HOME/.ssh/id_ed25519"
if [[ -f "$SSH_KEY" ]]; then
    check_pass "SSH key exists"
else
    check_fail "SSH key not found: $SSH_KEY"
fi

if [[ -f "${SSH_KEY}.pub" ]]; then
    check_pass "SSH public key exists"
else
    check_fail "SSH public key not found"
fi

# --- Git ---
print_header "Git"

if git config --global user.name &>/dev/null; then
    check_pass "Git user.name: $(git config --global user.name)"
else
    check_fail "Git user.name not set"
fi

if git config --global user.email &>/dev/null; then
    check_pass "Git user.email: $(git config --global user.email)"
else
    check_fail "Git user.email not set"
fi

# --- Hostname ---
print_header "Hostname"

if [[ "$(hostname)" == "$HOSTNAME" ]]; then
    check_pass "Hostname: $HOSTNAME"
else
    check_fail "Hostname mismatch: $(hostname) (expected: $HOSTNAME)"
fi

# --- Dotfiles ---
print_header "Dotfiles"

DOTFILES_DIR="$INSTALL_PATH/dotfiles"
if [[ -d "$DOTFILES_DIR" ]]; then
    dotfile_count=0
    for file in "$DOTFILES_DIR"/.*; do
        filename=$(basename "$file")
        [[ "$filename" == "." || "$filename" == ".." ]] && continue

        target="$HOME/$filename"
        if [[ -L "$target" ]]; then
            ((dotfile_count++))
        fi
    done

    if [[ $dotfile_count -gt 0 ]]; then
        check_pass "Dotfiles linked: $dotfile_count files"
    else
        check_fail "No dotfiles linked"
    fi
else
    log_warn "Dotfiles directory not found"
fi

# --- Docker ---
print_header "Docker"

if command -v docker &>/dev/null; then
    check_pass "Docker installed: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
    check_fail "Docker not installed"
fi

if docker compose version &>/dev/null; then
    check_pass "Docker Compose installed"
else
    check_fail "Docker Compose not installed"
fi

if docker info &>/dev/null 2>&1; then
    check_pass "Docker daemon running"
else
    check_fail "Docker daemon not running"
fi

if docker network inspect traefik-net &>/dev/null 2>&1; then
    check_pass "Network traefik-net exists"
else
    check_fail "Network traefik-net not found"
fi

# --- Summary ---
echo ""
print_separator

TOTAL=$((PASSED + FAILED))

if [[ $FAILED -eq 0 ]]; then
    print_footer "All checks passed ($PASSED/$TOTAL)"
else
    echo ""
    log_error "Failed: $FAILED/$TOTAL"
    log_info "Passed: $PASSED/$TOTAL"
    echo ""
    exit 1
fi
