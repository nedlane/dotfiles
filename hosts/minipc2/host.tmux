# hosts/minipc2/host.tmux — teal = minipc2.
# Prefix C-b (explicit) so it never clashes when nested inside the Mac
# (C-Space) or the desktop (C-a).
set -g prefix C-b
bind C-b send-prefix
set -g status-left-length 40
set -g status-left "#[bg=#94e2d5,fg=#11111b,bold]  #h #[bg=default,fg=#94e2d5,nobold] #S #[default]"
set -g pane-active-border-style "fg=#94e2d5"
