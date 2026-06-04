#!/usr/bin/env bash
# Bootstrap the current machine, then link the matching dotfiles overlay.
#
#   ./scripts/setup.sh              # auto-detect host
#   ./scripts/setup.sh wsl-desktop  # explicitly select a host
#
# mac and wsl-desktop receive the full profile. Other Linux hosts use their
# short hostname and receive the minimal homelab profile.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR="$DIR"
source "$DIR/scripts/lib/host.sh"

host="${1:-$(dotfiles_detect_host)}"
if [[ ! -d "$DIR/hosts/$host" ]]; then
  echo "Unknown host '$host' - no such directory: $DIR/hosts/$host" >&2
  exit 1
fi

clone() {
  [[ -d "$2" ]] || git clone --depth=1 "$1" "$2"
}

install_shell_tools() {
  echo "== oh-my-zsh =="
  export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
  if [[ ! -d "$ZSH" ]]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi
  ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"

  echo "== powerlevel10k + zsh plugins =="
  clone https://github.com/romkatv/powerlevel10k              "$ZSH_CUSTOM/themes/powerlevel10k"
  clone https://github.com/zsh-users/zsh-syntax-highlighting  "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  clone https://github.com/catppuccin/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/catppuccin_highlight" || true

  local hl_dir theme
  hl_dir="$ZSH_CUSTOM/plugins/catppuccin_highlight"
  if [[ -d "$hl_dir" && ! -f "$hl_dir/catppuccin_highlight.plugin.zsh" ]]; then
    theme="$(ls "$hl_dir"/*mocha*.zsh 2>/dev/null | head -1 || true)"
    [[ -n "$theme" ]] && printf 'source %q\n' "$theme" > "$hl_dir/catppuccin_highlight.plugin.zsh"
  fi

  echo "== tmux tpm =="
  clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
}

install_tmux_plugins() {
  echo "== install tmux plugins =="
  tmux -L dotfiles_setup -f "$HOME/.config/tmux/tmux.conf" new-session -d -s tpm 2>/dev/null || true
  tmux -L dotfiles_setup run-shell "$HOME/.config/tmux/plugins/tpm/bindings/install_plugins" 2>/dev/null || true
  tmux -L dotfiles_setup kill-server 2>/dev/null || true
}

setup_mac() {
  echo "== Homebrew =="
  if ! command -v brew >/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi

  local formula
  local -a formulae=(
    bash curl docker docker-completion docker-compose fd ffmpeg fmt fzf gh
    iproute2mac lua luarocks magic-wormhole neofetch neovim node php python
    rust scipy texlive tmux tree-sitter watchman wget yarn zsh
  )
  echo "== Homebrew packages =="
  for formula in "${formulae[@]}"; do
    brew list --formula "$formula" >/dev/null 2>&1 || brew install "$formula"
  done
  brew list --cask raycast >/dev/null 2>&1 || brew install --cask raycast
}

setup_wsl() {
  echo "== apt packages =="
  sudo apt-get update -y
  sudo apt-get install -y zsh tmux git curl fzf fd-find

  mkdir -p "$HOME/.local/bin"
  if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
}

setup_homelab() {
  local bin
  for bin in zsh tmux git curl; do
    command -v "$bin" >/dev/null || {
      echo "Missing required base package: $bin" >&2
      exit 1
    }
  done
  mkdir -p "$HOME/.local/bin"

  local nvim_version=v0.12.2
  local ts_version=v0.25.10
  local nvim_asset ts_asset
  case "$(uname -m)" in
    x86_64|amd64)
      nvim_asset=nvim-linux-x86_64
      ts_asset=tree-sitter-linux-x64
      ;;
    aarch64|arm64)
      nvim_asset=nvim-linux-arm64
      ts_asset=tree-sitter-linux-arm64
      ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac

  echo "== neovim $nvim_version (~/.local) =="
  if [[ "$("$HOME/.local/bin/nvim" --version 2>/dev/null | head -1)" != "NVIM $nvim_version" ]]; then
    curl -fsSL "https://github.com/neovim/neovim/releases/download/$nvim_version/$nvim_asset.tar.gz" -o /tmp/nvim.tar.gz
    tar -xzf /tmp/nvim.tar.gz -C "$HOME/.local"
    ln -sf "$HOME/.local/$nvim_asset/bin/nvim" "$HOME/.local/bin/nvim"
    rm -f /tmp/nvim.tar.gz
  fi

  echo "== tree-sitter CLI $ts_version (~/.local/bin) =="
  if [[ ! -x "$HOME/.local/bin/tree-sitter" ]]; then
    curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/download/$ts_version/$ts_asset.gz" \
      | gunzip > "$HOME/.local/bin/tree-sitter"
    chmod +x "$HOME/.local/bin/tree-sitter"
  fi

  echo "== fzf (~/.local/bin) =="
  if ! command -v fzf >/dev/null && [[ ! -x "$HOME/.local/bin/fzf" ]]; then
    clone https://github.com/junegunn/fzf "$HOME/.fzf"
    "$HOME/.fzf/install" --bin >/dev/null
    ln -sf "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf"
  fi
}

setup_homelab_service() {
  echo "== persistent tmux user service =="
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  loginctl enable-linger "$(whoami)" 2>/dev/null || true
  mkdir -p "$HOME/.config/systemd/user"
  ln -sf "$DIR/shared/systemd/user/tmux-main.service" "$HOME/.config/systemd/user/tmux-main.service"
  systemctl --user daemon-reload
  systemctl --user enable --now tmux-main.service
}

echo "host: $host"
case "$host" in
  mac) setup_mac ;;
  wsl-desktop) setup_wsl ;;
  *) setup_homelab ;;
esac

install_shell_tools

echo "== link dotfiles =="
"$DIR/scripts/link.sh" "$host"
install_tmux_plugins

if [[ "$host" != mac && "$host" != wsl-desktop ]]; then
  setup_homelab_service
fi

echo
echo "Done."
if [[ "${SHELL:-}" != *zsh ]]; then
  echo "Make zsh your login shell with:"
  echo "    chsh -s \"\$(command -v zsh)\""
fi
