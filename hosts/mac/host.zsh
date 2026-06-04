# hosts/mac/host.zsh — laptop-only zsh overlay. Sourced before oh-my-zsh.sh.

# laptop-only oh-my-zsh plugins
plugins+=(macos brew battery)

# Homebrew / macOS toolchain paths
export PATH="/opt/X11/bin:$PATH"
export OPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3

# Docker Desktop CLI completions
fpath=("$HOME/.docker/completions" $fpath)

# --- Tailscale desktop access (laptop only) ---
# Day-to-day: press  C-Space w  inside local tmux to jump to any desktop session.
# `desk`    -> in tmux, opens a fresh DEDICATED purple window (avoids nesting);
#             from a bare shell, recolors THIS window instead.
# `desk -w` -> always opens the fresh dedicated purple window.
desk() {
  local A=/Applications/Alacritty.app/Contents/MacOS/alacritty
  if [[ "$1" == "-w" || -n "$TMUX" ]]; then
    DESK_RECOLOR=0 "$A" --config-file "$HOME/.config/alacritty/desktop.toml" \
      -e "$HOME/.local/bin/desk" >/dev/null 2>&1 &
    disown
  else
    "$HOME/.local/bin/desk"
  fi
}

# --- machine identity (consumed by shared/zsh/zshrc) ---
# blue accent; prompt shows the actual hostname (%m)
export DOTFILES_ACCENT=111
# laptop: show the battery segment on the right (only the Mac opts in)
export DOTFILES_SHOW_BATTERY=1
