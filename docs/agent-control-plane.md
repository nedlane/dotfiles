# Desktop agent bridge

The desktop runs a deterministic Discord bridge alongside T3 Code. T3 Code is
the project workspace and provides linked-machine operations. The bridge maps
Discord channels to persistent workers; it does not call a model to route messages.

## Source and installation

Live source is the private `agent-bridge` submodule at
`~/dotfiles/hosts/wsl-desktop/agent-bridge`. Its `bin/` tools are linked into
`~/.local/bin` by `scripts/link.sh wsl-desktop`. The systemd user unit is
`claude-bridge`.

The submodule's README and command help document supported worker backends,
Discord commands and bridge configuration. Personal host instructions and device
access records live in `~/projects/orchestrator`.

## Workers and commands

Each configured project has a Discord channel and a worker named `cw-<name>`
in tmux. `agent-worker` manages Claude Code and Codex workers. Codex workers
support TUI and app-server backends; the channel configuration selects the harness.

```sh
agent-worker list
agent-worker status <name>
agent-worker read <name> 120
agent-worker send <name> "message"
bridge-ctl repos
```

Use `agent-worker --help` and `bridge-ctl --help` for lifecycle and configuration
operations. The bridge's `/harness` command selects a channel's engine.
Workers publish user-visible replies with `discord-notify`; terminal output
alone is not a delivery channel.

Worker state lives in `~/.local/state/claude-workers/<name>/`. Bridge configuration
lives in `~/.config/claude-bridge/config.json`. Keep credentials in their existing
stores and out of repositories, command output and logs.

## Apply configuration

```sh
./scripts/link.sh wsl-desktop
systemctl --user restart claude-bridge
systemctl --user status claude-bridge
```

The daemon loads configuration at startup, so restart it after changing daemon
code or bridge configuration. Workers survive the daemon restart. Worker CLI
changes are loaded on the next invocation.

Keep the service, workers and Discord channels active until an explicit shutdown
request. Changes to documentation do not require a service restart.
