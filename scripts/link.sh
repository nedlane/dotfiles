#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Safe multi-host dotfiles linker.
# Detects the host (or takes one as $1), records it, and symlinks the shared
# config + this host's overlay into place. NEVER deletes your data: anything
# real that's in the way is moved to a timestamped backup first.
#
#   ./scripts/link.sh              # auto-detect host
#   ./scripts/link.sh wsl-desktop  # force a host
# ---------------------------------------------------------------------------
set -euo pipefail

DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
BACKUP="$HOME/dotfiles-pre-link-backup-$(date +%Y%m%d-%H%M%S)"
source "$DIR/scripts/lib/host.sh"
changed=0

# --- detect host -----------------------------------------------------------
host="${1:-$(dotfiles_detect_host)}"
if [[ ! -d "$DIR/hosts/$host" ]]; then
  echo "Unknown host '$host' — no such dir: $DIR/hosts/$host" >&2
  exit 1
fi

# --- profile ---------------------------------------------------------------
# Every host shares the shell, tmux and nvim config. The profile only governs
# the shared gitconfig: "full" hosts (mac, wsl-desktop) link it; "minimal"
# hosts (the homelab boxes) skip it, because it enables SSH commit signing
# with a key they don't have, which would break their commits. Override with
# DOTFILES_PROFILE=full|minimal.
case "$host" in
  mac|wsl-desktop) profile=full ;;
  *)               profile=minimal ;;
esac
profile="${DOTFILES_PROFILE:-$profile}"

mkdir -p "$CFG"
echo "profile: $profile"
printf '%s\n' "$host" > "$CFG/host"
echo "host: $host"
echo

link_one() {
  local src="$1" dst="$2"
  [ -e "$src" ] || { echo "skip (no source): ${src#"$DIR"/}"; return; }
  mkdir -p "$(dirname "$dst")"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "ok        ${dst#"$HOME"/}"
    return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    mkdir -p "$BACKUP/$(dirname "${dst#"$HOME"/}")"
    mv "$dst" "$BACKUP/${dst#"$HOME"/}"
    echo "backed up ${dst#"$HOME"/}"
  fi
  ln -s "$src" "$dst"
  changed=1
  echo "linked    ${dst#"$HOME"/}"
}

# --- shell + tmux + editor (every host) ------------------------------------
link_one "$DIR/shared/zsh/zshrc"      "$HOME/.zshrc"
link_one "$DIR/shared/p10k.zsh"       "$HOME/.p10k.zsh"
link_one "$DIR/shared/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
# A stray ~/.tmux.conf would shadow the XDG path above — move it aside.
if [ -e "$HOME/.tmux.conf" ] && [ ! -L "$HOME/.tmux.conf" ]; then
  mkdir -p "$BACKUP"
  mv "$HOME/.tmux.conf" "$BACKUP/.tmux.conf"
  changed=1
  echo "backed up .tmux.conf (was shadowing XDG tmux.conf)"
fi
link_one "$DIR/shared/nvim"           "$HOME/.config/nvim"

# --- claude instructions (shared + optional host overlay) ------------------
# ~/.claude/CLAUDE.md is generated (not symlinked) so host-specific sections
# can be appended cleanly. Re-running link.sh regenerates it from source.
generate_claude_md() {
  local dst="$HOME/.claude/CLAUDE.md"
  local shared="$DIR/shared/claude/CLAUDE.md"
  local overlay="$DIR/hosts/$host/claude/CLAUDE.md"
  [ -e "$shared" ] || { echo "skip (no source): shared/claude/CLAUDE.md"; return; }
  mkdir -p "$(dirname "$dst")"

  # Build expected content into a temp file
  local tmp; tmp="$(mktemp)"
  cat "$shared" > "$tmp"
  [ -e "$overlay" ] && { printf '\n' >> "$tmp"; cat "$overlay" >> "$tmp"; }

  # Already up-to-date real file — nothing to do
  if [ -f "$dst" ] && [ ! -L "$dst" ] && diff -q "$tmp" "$dst" >/dev/null 2>&1; then
    echo "ok        .claude/CLAUDE.md"
    rm "$tmp"
    return
  fi

  # Back up any real file before overwriting
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    local bak="${BACKUP}/.claude/CLAUDE.md"
    mkdir -p "$(dirname "$bak")"
    cp "$dst" "$bak"
    echo "backed up .claude/CLAUDE.md"
  fi
  # Remove symlink (from a prior link_one run) so we write a real file
  [ -L "$dst" ] && rm "$dst"
  mv "$tmp" "$dst"
  if [ -e "$overlay" ]; then
    echo "generated .claude/CLAUDE.md (shared + $host overlay)"
  else
    echo "generated .claude/CLAUDE.md (shared only)"
  fi
  changed=1
}
generate_claude_md

# --- git (full profile only) -----------------------------------------------
# The shared gitconfig turns on SSH commit signing with a key the homelab
# boxes don't have; linking it there would break their commits.
if [[ "$profile" == full ]]; then
  link_one "$DIR/shared/git/gitconfig" "$HOME/.gitconfig"
else
  echo "skip (minimal profile): .gitconfig"
fi

# --- host overlay ----------------------------------------------------------
# host.zsh is sourced directly by ~/.zshrc via $DOTFILES_HOST (not symlinked).
link_one "$DIR/hosts/$host/host.tmux" "$CFG/host.tmux"
[ -e "$DIR/hosts/$host/gitconfig" ] && link_one "$DIR/hosts/$host/gitconfig" "$CFG/gitconfig.host"

# --- shared CLI tools (all hosts) ------------------------------------------
# The `prefix w` switcher (and any future shared/bin tools), linked per-file
# into ~/.local/bin (which holds other machine-local tools, so we don't symlink
# the whole dir).
for tool in "$DIR"/shared/bin/*; do
  link_one "$tool" "$HOME/.local/bin/$(basename "$tool")"
done

# --- mac-only extras -------------------------------------------------------
if [[ "$host" == mac ]]; then
  link_one "$DIR/hosts/mac/alacritty" "$HOME/.config/alacritty"
  # Tailscale desktop-access convenience commands (Mac client only).
  for tool in desk desk-attach; do
    link_one "$DIR/hosts/mac/bin/$tool" "$HOME/.local/bin/$tool"
  done
fi

echo
if [[ "$changed" == 1 ]]; then
  echo "Replaced files saved to: $BACKUP"
else
  echo "All links already in place — nothing to back up."
fi
