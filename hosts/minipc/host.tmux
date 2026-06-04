# hosts/minipc/host.tmux — green = minipc.
# Prefix C-b (explicit) so it never clashes when nested inside the Mac
# (C-Space) or the desktop (C-a).
set -g prefix C-b
bind C-b send-prefix
set -g status-left-length 40
set -g status-left "#[bg=#a6e3a1,fg=#11111b,bold]  #h #[bg=default,fg=#a6e3a1,nobold] #S #[default]"
set -g pane-active-border-style "fg=#a6e3a1"
