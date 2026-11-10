# dev1 VPS uses C-b for nested tmux sessions.
set -g prefix C-b
bind C-b send-prefix
set -g @host_accent "#cba6f7"
set -g @host_label "dev1"
set -g pane-active-border-style "fg=#cba6f7"
source-file -q ~/.config/tmux/persist-sessions.tmux
