# ===========================================
# Homelab Zsh Configuration
# ===========================================

# Helpers
has() { command -v "$1" > /dev/null 2>&1; }
try_source() { [[ -s "$1" ]] && source "$1"; }

# -------------------------------------------
# Oh My Zsh
# -------------------------------------------

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
ZSH_DISABLE_COMPFIX="true"

plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-history-substring-search
)

source $ZSH/oh-my-zsh.sh

# -------------------------------------------
# Environment
# -------------------------------------------

export EDITOR='nano'
export VISUAL='nano'
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export HOMELAB_PATH="/opt/homelab"

# -------------------------------------------
# Path
# -------------------------------------------

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# -------------------------------------------
# History
# -------------------------------------------

HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt share_history
setopt appendhistory
setopt inc_append_history
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt extended_history

# -------------------------------------------
# Key bindings (↑/↓ history substring search)
# -------------------------------------------

bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey "$terminfo[kcuu1]" history-substring-search-up
bindkey "$terminfo[kcud1]" history-substring-search-down

# -------------------------------------------
# mise - polyglot version manager
# -------------------------------------------

has mise && eval "$(mise activate zsh)"

# -------------------------------------------
# fzf configuration (use fd for speed)
# -------------------------------------------

export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always --line-range :500 {}'"

# -------------------------------------------
# Tools initialization
# -------------------------------------------

has rgrc && eval "$(rgrc --aliases)"
has zoxide && eval "$(zoxide init zsh --cmd cd)"
has starship && eval "$(starship init zsh)"
try_source ~/.aliases
