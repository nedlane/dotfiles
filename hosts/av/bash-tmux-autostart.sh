# hosts/av/bash-tmux-autostart.sh — sourced from ~/.bashrc on av.
#
# av runs bash (not the shared zsh stack), so replicate the zsh autostart from
# shared/zsh/zshrc here: land straight in a persistent "main" tmux session on
# any interactive login, so `ssh av` attaches to the tmux server instead of a
# bare shell. Guards skip non-interactive shells (the Claude worker's `bash -s`
# / `bash -lc` automation), shells already inside tmux, and editor/agent shells.
if command -v tmux >/dev/null 2>&1 \
   && [[ $- == *i* ]] && [[ -z "$TMUX" ]] \
   && [[ "$TERM_PROGRAM" != vscode && -z "$VSCODE_INJECTION" ]] \
   && [[ -z "$INSIDE_EMACS" ]]; then
  exec tmux new -A -s main
fi
