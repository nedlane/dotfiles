# hosts/minipc2/host.tmux — teal = minipc2.
# Prefix C-b (explicit) so it never clashes when nested inside the Mac
# (C-Space) or the desktop (C-a).
set -g prefix C-b
bind C-b send-prefix

# Device identity consumed by the shared status bar (catppuccin teal).
set -g @host_accent "#94e2d5"
set -g @host_label " minipc2"
set -g pane-active-border-style "fg=#94e2d5"

# Always-on box: keep tmux across reboot. Sourced here (after the status bar) on
# purpose — see the snippet's header. mac never sources this.
source-file -q ~/.config/tmux/persist-sessions.tmux
