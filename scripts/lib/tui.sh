#!/bin/bash
# ===========================================
# TUI Library for Homelab Scripts
# ===========================================
# Source this file in your scripts:
#   source "$(dirname "$0")/lib/tui.sh"
#
# Available functions:
#   log_info, log_warn, log_error, log_step
#   print_header, print_footer
#   confirm, press_enter
#   spinner_start, spinner_stop

# -------------------------------------------
# Colors
# -------------------------------------------

# Check if terminal supports colors
if [[ -t 1 ]] && [[ -n "$TERM" ]] && command -v tput &> /dev/null; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    WHITE=$(tput setaf 7)
    BOLD=$(tput bold)
    NC=$(tput sgr0)  # No Color / Reset
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[0;37m'
    BOLD='\033[1m'
    NC='\033[0m'
fi

# -------------------------------------------
# Logging Functions
# -------------------------------------------

log_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[→]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${MAGENTA}[D]${NC} $1"
    fi
}

# -------------------------------------------
# Headers and Separators
# -------------------------------------------

print_header() {
    local title="$1"
    local width=45
    echo ""
    echo -e "${BLUE}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo -e "${BLUE}  ${title}${NC}"
    echo -e "${BLUE}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo ""
}

print_footer() {
    local title="$1"
    local width=45
    echo ""
    echo -e "${GREEN}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo -e "${GREEN}  ${title}${NC}"
    echo -e "${GREEN}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo ""
}

print_box() {
    local title="$1"
    local width=45
    echo ""
    echo -e "${CYAN}╔$(printf '═%.0s' $(seq 1 $((width-2))))╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}${title}${NC}$(printf ' %.0s' $(seq 1 $((width-4-${#title}))))${CYAN}║${NC}"
    echo -e "${CYAN}╚$(printf '═%.0s' $(seq 1 $((width-2))))╝${NC}"
    echo ""
}

print_separator() {
    echo -e "${BLUE}───────────────────────────────────────────${NC}"
}

# -------------------------------------------
# Interactive Functions
# -------------------------------------------

confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-y}"

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi

    read -p "$prompt" -n 1 -r
    echo

    if [[ -z "$REPLY" ]]; then
        REPLY="$default"
    fi

    [[ "$REPLY" =~ ^[Yy]$ ]]
}

press_enter() {
    # Skip in test mode
    if [[ "${TEST_MODE:-0}" == "1" ]]; then
        log_info "[TEST] Skipping interactive prompt"
        return 0
    fi

    local prompt="${1:-Press Enter to continue...}"
    echo ""
    echo -e "${GREEN}[→]${NC} $prompt"
    read
    echo ""
}

# -------------------------------------------
# Spinner / Progress
# -------------------------------------------

# Spinner characters
SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
SPINNER_PID=""

spinner_start() {
    local message="${1:-Loading...}"

    (
        i=0
        while true; do
            printf "\r${BLUE}[${SPINNER_CHARS:$i:1}]${NC} %s" "$message"
            i=$(( (i + 1) % ${#SPINNER_CHARS} ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown
}

spinner_stop() {
    local status="${1:-done}"

    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=""
    fi

    # Clear the line
    printf "\r\033[K"

    if [[ "$status" == "done" ]]; then
        log_info "Done"
    elif [[ "$status" == "fail" ]]; then
        log_error "Failed"
    fi
}

# Run command with spinner
run_with_spinner() {
    local message="$1"
    shift
    local cmd="$@"

    spinner_start "$message"

    if eval "$cmd" > /dev/null 2>&1; then
        spinner_stop "done"
        return 0
    else
        spinner_stop "fail"
        return 1
    fi
}

# -------------------------------------------
# Progress Bar
# -------------------------------------------

progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-40}
    local prefix="${4:-Progress}"

    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r%s: [" "$prefix"
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$percent"

    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# -------------------------------------------
# Input Functions
# -------------------------------------------

read_input() {
    local prompt="$1"
    local default="${2:-}"
    local result

    if [[ -n "$default" ]]; then
        read -p "${prompt} [${default}]: " result
        result="${result:-$default}"
    else
        read -p "${prompt}: " result
    fi

    echo "$result"
}

read_secret() {
    local prompt="$1"
    local result

    read -s -p "${prompt}: " result
    echo ""  # New line after hidden input

    echo "$result"
}

# -------------------------------------------
# Utility Functions
# -------------------------------------------

# Check if running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Check if command exists
has_command() {
    command -v "$1" &> /dev/null
}

# Die with error message
die() {
    log_error "$1"
    exit "${2:-1}"
}

# -------------------------------------------
# Verification Functions
# -------------------------------------------

# Check if apt package is installed
require_package() {
    local pkg="$1"
    if ! dpkg -s "$pkg" &>/dev/null; then
        log_error "Package '$pkg' is not installed"
        return 1
    fi
}

# Check if command is available
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Command '$cmd' not found"
        return 1
    fi
}

# Get user's default shell from /etc/passwd (not $SHELL)
get_user_shell() {
    getent passwd "$USER" | cut -d: -f7
}

# Trap cleanup
cleanup_trap() {
    spinner_stop "fail"
    echo ""
    log_error "Script interrupted"
    exit 1
}

# Setup trap for clean exit
trap cleanup_trap INT TERM
