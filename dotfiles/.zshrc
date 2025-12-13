# ===========================================
# Homelab Zsh Configuration
# ===========================================

# Path to oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="robbyrussell"

# Plugins
plugins=(
    git
    docker
    docker-compose
    zsh-autosuggestions
    zsh-syntax-highlighting
    history-substring-search
)

# Load oh-my-zsh
source $ZSH/oh-my-zsh.sh

# -------------------------------------------
# Environment
# -------------------------------------------

export EDITOR='micro'
export VISUAL='micro'
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Homelab path
export HOMELAB_PATH="/opt/homelab"

# -------------------------------------------
# Path
# -------------------------------------------

export PATH="$HOME/.local/bin:$PATH"

# -------------------------------------------
# History
# -------------------------------------------

HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY

# -------------------------------------------
# Aliases
# -------------------------------------------

# Load custom aliases
[[ -f ~/.aliases ]] && source ~/.aliases

# -------------------------------------------
# Zellij auto-start
# -------------------------------------------

# Auto-start zellij on SSH sessions (attach to existing or create new)
if [[ -z "$ZELLIJ" && -n "$SSH_CONNECTION" ]]; then
    eval "$(zellij setup --generate-auto-start zsh)"
fi

# -------------------------------------------
# History substring search (↑/↓ with typed prefix)
# -------------------------------------------

# Bind ↑ and ↓ arrows to history-substring-search
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Also bind for terminals that send different codes
bindkey "$terminfo[kcuu1]" history-substring-search-up
bindkey "$terminfo[kcud1]" history-substring-search-down

# -------------------------------------------
# Custom prompt additions
# -------------------------------------------

# Show hostname in prompt (useful for SSH)
# PROMPT="%{$fg[cyan]%}%m%{$reset_color%} $PROMPT"
