# hosts/pi/host.tmux — red = Raspberry Pi.
# Prefix C-b (explicit) so it never clashes when nested inside the Mac
# (C-Space) or the desktop (C-a).
set -g prefix C-b
bind C-b send-prefix

# Device identity consumed by the shared status bar (catppuccin red).
set -g @host_accent "#f38ba8"
set -g @host_label " pi"
set -g pane-active-border-style "fg=#f38ba8"
