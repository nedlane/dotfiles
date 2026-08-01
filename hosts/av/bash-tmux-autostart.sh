# hosts/av/bash-tmux-autostart.sh — sourced from ~/.bashrc on av.
#
# av runs bash (not the shared zsh stack), so replicate the zsh autostart from
# shared/zsh/zshrc here: land straight in a persistent "main" tmux session on
# any interactive login, so `ssh av` attaches to the tmux server instead of a
# bare shell. Guards skip non-interactive shells (the Claude worker's `bash -s`
# / `bash -lc` automation), shells already inside tmux, and editor/agent shells.
if command -v tmux >/dev/null 2>&1    && [[ $- == *i* ]] && [[ -z "$TMUX" ]]    && [[ "$TERM_PROGRAM" != vscode && -z "$VSCODE_INJECTION" ]]    && [[ -z "$INSIDE_EMACS" ]]; then
  # If the client's TERM is not in this host's terminfo DB (e.g. xterm-kitty
  # from a kitty terminal), tmux — and much else — fails with "missing or
  # unsuitable terminal". Fall back to a universally-present entry so the
  # session still works. (kitty itself endorses this fallback.)
  if ! infocmp "$TERM" >/dev/null 2>&1; then
    export TERM=xterm-256color
  fi
  # NOT exec: if tmux still fails for any reason, we drop to a usable login
  # shell instead of the SSH connection dying. On a clean detach tmux returns
  # 0 and we exit, closing the ssh session as expected.
  tmux new -A -s main && exit
fi
