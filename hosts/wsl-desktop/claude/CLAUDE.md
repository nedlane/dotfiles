## Agent bridge & worker fleet (this host)

This desktop runs a Discord-driven agent fleet. Each project maps to a Discord
channel backed by a tmux worker session `cw-<name>` running Claude Code or
Codex; the `agent-bridge` daemon (systemd `--user` unit `claude-bridge`) relays
Discord ↔ workers. Fleet config: `~/.config/claude-bridge/config.json`.

Tools (in `~/.local/bin`, symlinked from the LIVE checkout — the dotfiles
submodule `~/dotfiles/hosts/wsl-desktop/agent-bridge`, NOT the standalone clone
at `~/projects/agent-bridge`):

- `agent-worker <list|start|stop|send|read|key> <name>` — drive a worker's tmux
  session directly.
- `bridge-ctl <repos|addrepo|rename|categories|request|...>` — manage the
  channel↔repo mappings and guest access.
- `discord-notify "msg"` (also `… | discord-notify -`, `-t discord:<chan>`) —
  message Ned on Discord. Bridge workers MUST reply with this; their terminal
  output is not visible to him.

Engines: each channel runs `claude` or `codex`, switched with the `/harness`
Discord command (`codex` = YOLO — bypass approvals + sandbox). **Codex is the
default** for newly added repos; existing channels carry an explicit harness in
config.

Deploy: the daemon loads config ONCE at startup (no hot reload), so after
editing config or `bin/`, restart it — `systemctl --user restart claude-bridge`
(the `cw-*` workers survive). `agent-worker` is exec'd fresh per action, so its
edits need no restart. LIVE code is the dotfiles submodule; editing the
`~/projects/agent-bridge` clone does NOT change the running system — deploy by
getting code into the submodule, then `scripts/link.sh`, then restart.

Web console: the browser UI for the fleet is the separate `claude-worker-webui`
project (desktop `worker-api.py` :8790 + minipc SPA :8080) — see
`~/projects/agent-bridge/CLAUDE.md` for access + edit details.
