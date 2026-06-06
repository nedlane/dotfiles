# hosts/wsl-desktop/host.tmux — sourced after the shared status bar, so it wins.
# Purple = "this is the desktop". Prefix remapped to C-a to avoid nesting
# clashes with the laptop's C-Space.

unbind C-b
set -g prefix C-a
bind C-a send-prefix

# Device identity consumed by the shared status bar (catppuccin mauve).
set -g @host_accent "#cba6f7"
set -g @host_label " desktop"
set -g pane-active-border-style "fg=#cba6f7"
