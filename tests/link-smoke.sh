#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hosts=(mac wsl-desktop minipc minipc2 pi)

fail() {
  echo "link smoke test failed: $*" >&2
  exit 1
}

assert_link() {
  local path=$1 target=$2
  [[ -L "$path" ]] || fail "$path is not a symlink"
  [[ "$(readlink "$path")" == "$target" ]] || fail "$path points to $(readlink "$path"), expected $target"
}

for host in "${hosts[@]}"; do
  home="$(mktemp -d)"
  trap 'rm -rf "${home:-}"' EXIT

  mkdir -p "$home/.config"
  printf 'existing zshrc\n' > "$home/.zshrc"
  printf 'shadowing tmux config\n' > "$home/.tmux.conf"

  HOME="$home" XDG_CONFIG_HOME="$home/.config" DOTFILES_DIR="$ROOT" \
    "$ROOT/scripts/link.sh" "$host" > "$home/first-link.log"

  assert_link "$home/.zshrc" "$ROOT/shared/zsh/zshrc"
  assert_link "$home/.p10k.zsh" "$ROOT/shared/p10k.zsh"
  assert_link "$home/.config/tmux/tmux.conf" "$ROOT/shared/tmux/tmux.conf"
  assert_link "$home/.config/nvim" "$ROOT/shared/nvim"
  assert_link "$home/.config/git/ignore" "$ROOT/shared/git/ignore"
  assert_link "$home/.config/dotfiles/host.tmux" "$ROOT/hosts/$host/host.tmux"
  assert_link "$home/.local/bin/tmux-switch" "$ROOT/shared/bin/tmux-switch"
  assert_link "$home/.local/bin/claude-launch" "$ROOT/shared/bin/claude-launch"
  [[ "$(cat "$home/.config/dotfiles/host")" == "$host" ]] || fail "recorded host does not match $host"

  backup="$(find "$home" -maxdepth 1 -type d -name 'dotfiles-pre-link-backup-*' -print -quit)"
  [[ -n "$backup" ]] || fail "$host did not create a backup"
  [[ -f "$backup/.zshrc" ]] || fail "$host did not back up .zshrc"
  [[ -f "$backup/.tmux.conf" ]] || fail "$host did not back up shadowing .tmux.conf"

  case "$host" in
    mac)
      assert_link "$home/.gitconfig" "$ROOT/shared/git/gitconfig"
      assert_link "$home/.config/alacritty" "$ROOT/hosts/mac/alacritty"
      assert_link "$home/.local/bin/desk" "$ROOT/hosts/mac/bin/desk"
      assert_link "$home/.local/bin/desk-attach" "$ROOT/hosts/mac/bin/desk-attach"
      ;;
    wsl-desktop)
      assert_link "$home/.gitconfig" "$ROOT/shared/git/gitconfig"
      [[ ! -e "$home/.config/alacritty" ]] || fail "$host unexpectedly linked Alacritty"
      for tool in claude-worker claude-worker-todo-relay agent-checkup; do
        assert_link "$home/.local/bin/$tool" "$ROOT/hosts/wsl-desktop/bin/$tool"
      done
      assert_link "$home/.hermes/skills/claude-workers" \
        "$ROOT/hosts/wsl-desktop/hermes/skills/claude-workers"
      assert_link "$home/.claude/skills/discord-notify" \
        "$ROOT/hosts/wsl-desktop/claude/skills/discord-notify"
      ;;
    *)
      [[ ! -e "$home/.gitconfig" ]] || fail "$host unexpectedly linked the full-profile Git config"
      ;;
  esac

  # The agent control plane is desktop-only.
  case "$host" in
    wsl-desktop) ;;
    *)
      [[ ! -e "$home/.local/bin/claude-worker" ]] \
        || fail "$host unexpectedly linked the desktop-only claude-worker"
      ;;
  esac

  HOME="$home" XDG_CONFIG_HOME="$home/.config" DOTFILES_DIR="$ROOT" \
    "$ROOT/scripts/link.sh" "$host" > "$home/second-link.log"
  grep -q 'All links already in place' "$home/second-link.log" || fail "$host relink was not idempotent"

  rm -rf "$home"
  trap - EXIT
done

home="$(mktemp -d)"
trap 'rm -rf "$home"' EXIT
HOME="$home" XDG_CONFIG_HOME="$home/.config" DOTFILES_DIR="$ROOT" DOTFILES_PROFILE=full \
  "$ROOT/scripts/link.sh" minipc >/dev/null
assert_link "$home/.gitconfig" "$ROOT/shared/git/gitconfig"

if HOME="$home" XDG_CONFIG_HOME="$home/.config" DOTFILES_DIR="$ROOT" \
  "$ROOT/scripts/link.sh" definitely-not-a-host >/dev/null 2>&1; then
  fail "unknown host unexpectedly succeeded"
fi

echo "link smoke tests passed"
