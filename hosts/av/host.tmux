# hosts/av/host.tmux — peach = av (the autonomous race-car Jetson).
# Prefix C-b (explicit, homelab style) so it never clashes when nested inside
# the Mac (C-Space) or the desktop (C-a).
set -g prefix C-b
bind C-b send-prefix

# This box runs bash, not zsh — override the shared config's zsh pin so tmux
# panes spawn the shell the car actually uses. Sourced last, so it wins.
set -g default-shell /usr/bin/bash
set -g default-command /usr/bin/bash

# Device identity consumed by the shared status bar (catppuccin peach).
set -g @host_accent "#fab387"
set -g @host_label " av"
set -g pane-active-border-style "fg=#fab387"

# Always-on box: keep tmux across reboot. Sourced here (after the status bar) on
# purpose — see the snippet's header. mac never sources this.
source-file -q ~/.config/tmux/persist-sessions.tmux
