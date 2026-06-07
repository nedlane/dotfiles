# hosts/minipc2/host.zsh — mini PC #2 overlay. Sourced before oh-my-zsh.sh.

# extra oh-my-zsh plugins this box had before adopting the shared config
plugins+=(brew globalias)

# host-specific alias
alias docker-compose="docker compose"

# --- machine identity (consumed by shared/zsh/zshrc) ---
# teal accent (matches the tmux switcher color); prompt shows the hostname.
export DOTFILES_ACCENT=116
export DOTFILES_ACCENT_HEX="#94e2d5"
