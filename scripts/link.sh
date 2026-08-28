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
# Inert helper: only the always-on hosts' overlays `source-file` it (mac never
# does), so linking it everywhere is harmless — it does nothing unless sourced.
link_one "$DIR/shared/tmux/persist-sessions.tmux" "$HOME/.config/tmux/persist-sessions.tmux"
# A stray ~/.tmux.conf would shadow the XDG path above — move it aside.
if [ -e "$HOME/.tmux.conf" ] && [ ! -L "$HOME/.tmux.conf" ]; then
  mkdir -p "$BACKUP"
  mv "$HOME/.tmux.conf" "$BACKUP/.tmux.conf"
  changed=1
  echo "backed up .tmux.conf (was shadowing XDG tmux.conf)"
fi
link_one "$DIR/shared/nvim"           "$HOME/.config/nvim"
# Global Git ignore — Git auto-reads this XDG path regardless of profile, so
# even minimal hosts (which skip the shared gitconfig) get the ignore rules.
link_one "$DIR/shared/git/ignore"     "${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"

# --- agent instructions (shared + optional host overlay) -------------------
# Claude and Codex receive the same generated policy so they cannot drift.
# Real files allow host-specific sections to be appended cleanly.
generate_agent_instructions() {
  local dst="$1"
  local display_path="$2"
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
    echo "ok        $display_path"
    rm "$tmp"
    return
  fi

  # Back up any real file before overwriting
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    local bak="${BACKUP}/$display_path"
    mkdir -p "$(dirname "$bak")"
    cp "$dst" "$bak"
    echo "backed up $display_path"
  fi
  # Remove symlink (from a prior link_one run) so we write a real file
  [ -L "$dst" ] && rm "$dst"
  mv "$tmp" "$dst"
  if [ -e "$overlay" ]; then
    echo "generated $display_path (shared + $host overlay)"
  else
    echo "generated $display_path (shared only)"
  fi
  changed=1
}
generate_agent_instructions "$HOME/.claude/CLAUDE.md" ".claude/CLAUDE.md"
generate_agent_instructions "$HOME/.codex/AGENTS.md" ".codex/AGENTS.md"

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

# --- always-on hosts: tmux server at boot -----------------------------------
# Every host except the mac sources persist-sessions.tmux (resurrect +
# continuum), and pairs it with a user unit that starts the tmux server at
# boot — so continuum's restore runs detached, before anyone ssh'es in.
# Enable once per host: systemctl --user daemon-reload && systemctl --user enable --now tmux-main
if [[ "$host" != mac ]]; then
  link_one "$DIR/shared/systemd/user/tmux-main.service" \
    "$HOME/.config/systemd/user/tmux-main.service"
fi

# --- desktop-only extras ----------------------------------------------------
# The agent control plane (claude-worker & friends) runs only on the desktop;
# other hosts just get the shared claude-launch above. It lives in the
# `agent-bridge` submodule (hosts/wsl-desktop/agent-bridge/) — run
# `git submodule update --init` if the dir is empty.
if [[ "$host" == wsl-desktop ]]; then
  for tool in "$DIR"/hosts/wsl-desktop/agent-bridge/bin/*; do
    [ -f "$tool" ] || continue   # skip a stray __pycache__/ dir
    link_one "$tool" "$HOME/.local/bin/$(basename "$tool")"
  done
  # Claude Code skills: pinging Ned on Discord, managing the bridge.
  for skill in discord-notify claude-bridge; do
    link_one "$DIR/hosts/wsl-desktop/agent-bridge/skills/$skill" \
      "$HOME/.claude/skills/$skill"
  done
  # The Discord<->worker bridge daemon (enable: systemctl --user enable --now claude-bridge).
  link_one "$DIR/hosts/wsl-desktop/agent-bridge/systemd/claude-bridge.service" \
    "$HOME/.config/systemd/user/claude-bridge.service"
fi

# --- mac-only extras -------------------------------------------------------
if [[ "$host" == mac ]]; then
  link_one "$DIR/hosts/mac/alacritty" "$HOME/.config/alacritty"
  link_one "$DIR/hosts/mac/kitty" "$HOME/.config/kitty"
  # Tailscale desktop-access convenience commands (Mac client only).
  for tool in desk desk-attach kitty-tmux-main; do
    link_one "$DIR/hosts/mac/bin/$tool" "$HOME/.local/bin/$tool"
  done
fi

echo
if [[ "$changed" == 1 ]]; then
  echo "Replaced files saved to: $BACKUP"
else
  echo "All links already in place — nothing to back up."
fi
