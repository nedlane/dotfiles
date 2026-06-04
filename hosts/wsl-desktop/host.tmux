# hosts/wsl-desktop/host.tmux — sourced after catppuccin, so it wins.
# Purple = "this is the desktop". Prefix remapped to C-a to avoid nesting
# clashes with the laptop's C-Space.

unbind C-b
set -g prefix C-a
bind C-a send-prefix

# machine badge + accent (catppuccin mauve)
set -g status-left-length 40
set -g status-left "#[bg=#cba6f7,fg=#11111b,bold]  DESKTOP #[bg=default,fg=#cba6f7,nobold] #S #[default]"
set -g pane-active-border-style "fg=#cba6f7"
