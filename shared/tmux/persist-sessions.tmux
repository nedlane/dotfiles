# shared/tmux/persist-sessions.tmux — OPT-IN snippet, NOT auto-loaded.
#
# Keeps tmux sessions/windows/panes alive across a full reboot or `wsl
# --shutdown` via tmux-resurrect (save/restore) + tmux-continuum (auto-save on a
# timer, auto-restore the moment the server starts — e.g. the systemd `main`
# unit on boot). This is a property of ALWAYS-ON hosts only, so it lives here as
# an inert library file rather than in shared/tmux/tmux.conf: a host opts in with
#   source-file -q ~/.config/tmux/persist-sessions.tmux
# in its hosts/<host>/host.tmux. The mac laptop deliberately never sources it.
# (Same shared-but-selectively-deployed pattern as shared/systemd/tmux-main.service.)
#
# ORDERING: host overlays are sourced at the very END of tmux.conf — after
# `run tpm` AND after the hand-rolled status bar. That matters here for two
# reasons:
#   1. tpm has already run, so it will NOT auto-source these two plugins; we load
#      them by hand below (guarded so a not-yet-installed plugin is a no-op on a
#      fresh box — `setup.sh` installs them on next run via tpm).
#   2. continuum drives its auto-save by injecting #(continuum_save.sh) into
#      status-right. Loading it HERE, after our custom status-right is set, means
#      the hook lands on the final bar instead of being clobbered — which is
#      exactly the bug you hit if these plugins load via tpm before the bar.

# Declared so `tpm`'s installer (which reads @plugin from a throwaway server that
# sources this overlay — see setup.sh install_tmux_plugins) clones them.
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

# Restore captured pane text and nvim sessions, not just the bare layout.
set -g @resurrect-capture-pane-contents 'on'
set -g @resurrect-strategy-nvim 'session'

# Auto-restore when the server starts; auto-save every 15 minutes.
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'

# Load the plugins now (tpm already passed). Guard on the file existing so a
# fresh checkout before `prefix + I` / setup.sh just no-ops instead of erroring.
# resurrect first — continuum depends on it.
if-shell '[ -e ~/.config/tmux/plugins/tmux-resurrect/resurrect.tmux ]' \
  "run-shell '~/.config/tmux/plugins/tmux-resurrect/resurrect.tmux'"
if-shell '[ -e ~/.config/tmux/plugins/tmux-continuum/continuum.tmux ]' \
  "run-shell '~/.config/tmux/plugins/tmux-continuum/continuum.tmux'"
