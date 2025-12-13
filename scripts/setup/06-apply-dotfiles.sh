#!/bin/bash
# ===========================================
# Step 06: Apply Dotfiles
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tui.sh"

# -------------------------------------------

print_header "Step 7/9: Applying dotfiles"

DOTFILES_DIR="$INSTALL_PATH/dotfiles"

if [[ ! -d "$DOTFILES_DIR" ]]; then
    log_error "Dotfiles directory not found: $DOTFILES_DIR"
    exit 1
fi

# Backup existing files
backup_dir="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$backup_dir"

# Apply each dotfile
for file in "$DOTFILES_DIR"/.*; do
    filename=$(basename "$file")

    # Skip . and ..
    [[ "$filename" == "." || "$filename" == ".." ]] && continue

    target="$HOME/$filename"

    # Backup if exists and not a symlink
    if [[ -f "$target" && ! -L "$target" ]]; then
        mv "$target" "$backup_dir/"
        log_step "Backed up: $filename"
    fi

    # Remove existing symlink
    [[ -L "$target" ]] && rm "$target"

    # Create symlink
    ln -s "$file" "$target"

    # Verify symlink
    if [[ -L "$target" && "$(readlink "$target")" == "$file" ]]; then
        log_info "Linked: $filename"
    else
        log_error "Failed to link: $filename"
        exit 1
    fi
done

log_info "Dotfiles applied"
