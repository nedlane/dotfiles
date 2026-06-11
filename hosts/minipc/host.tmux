# hosts/minipc/host.tmux — green = minipc.
# Prefix C-b (explicit) so it never clashes when nested inside the Mac
# (C-Space) or the desktop (C-a).
set -g prefix C-b
bind C-b send-prefix

# Device identity consumed by the shared status bar (catppuccin green).
set -g @host_accent "#a6e3a1"
set -g @host_label " minipc"
set -g pane-active-border-style "fg=#a6e3a1"

# Always-on box: keep tmux across reboot. Sourced here (after the status bar) on
# purpose — see the snippet's header. mac never sources this.
source-file -q ~/.config/tmux/persist-sessions.tmux
