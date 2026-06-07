# hosts/mac/host.tmux — sourced after the shared status bar, so it wins.
# Blue = "this is the laptop". Prefix stays C-Space.

unbind C-b
set -g prefix C-Space
bind C-Space send-prefix

# Homebrew zsh — must be explicit since tmux freezes $SHELL at server-start time.
set -g default-shell /opt/homebrew/bin/zsh
set -g default-command /opt/homebrew/bin/zsh

# Device identity consumed by the shared status bar (catppuccin blue).
set -g @host_accent "#89b4fa"
set -g @host_label " mac"
set -g pane-active-border-style "fg=#89b4fa"

# --- Tailscale desktop access (laptop is a client of the always-on WSL box) ---
# The unified `prefix w` switcher (local + all Tailscale peers) is now shared
# across every host; see shared/tmux/tmux.conf and shared/bin/tmux-switch.

# Nested tmux: your -n binds (C-h/j/k/l, M-H/M-L) and the prefix live in the
# OUTER (local) tmux, so F12 flips the outer to an empty "off" table => every
# key falls through to the remote tmux. Status bar turns purple while handed
# over. F12 again to return.
bind -T root F12 set prefix None \; set key-table off \; set status-style 'bg=#221240,fg=#cdd6f4' \; refresh-client -S
bind -T off  F12 set -u prefix \; set -u key-table \; set -u status-style \; refresh-client -S
