# hosts/pi/host.zsh — Raspberry Pi overlay. Sourced before oh-my-zsh.sh.

# extra oh-my-zsh plugins this box had before adopting the shared config
plugins+=(brew globalias)

# --- machine identity (consumed by shared/zsh/zshrc) ---
# red accent (matches the tmux switcher color); prompt shows the hostname.
export DOTFILES_ACCENT=211
export DOTFILES_ACCENT_HEX="#f38ba8"
