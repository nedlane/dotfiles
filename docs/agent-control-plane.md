# Local agent control plane

Desktop-only setup that turns Discord into a remote control for interactive
Claude Code workers running in tmux on this machine. There is **no LLM in
the routing path** — a small deterministic bridge maps Discord channels to
workers; Claude Code, on the Claude subscription via its normal interactive
login, is the only intelligence. No Anthropic API keys, no OpenRouter, no
provider billing, anywhere.

```
        Discord                  #<repo> channels under the "Claude" category
            │  bot (gateway connection, Message Content intent)
            ▼
      claude-bridge              deterministic pipe; python daemon
            │                    (systemd user service, no LLM)
            │  claude-worker start/send
            ▼
     claude-worker …             (hosts/wsl-desktop/bin, desktop-only)
            │  tmux sessions cw-<name>
            ▼
      claude-launch              (shared/bin, used by `cl` everywhere)
            │
            ▼
  interactive Claude Code        (Claude subscription, remote-control mode)
       │                │
       │                └─ discord-notify / todo relay → repo channel
       │  Stop hook (claude-worker-done-relay, signed localhost event)
       ▼
      claude-bridge ───────────▶ worker's reply posted to the repo channel
```

## Model

- **Channel-per-repo, one worker per repo, no threads.** A config file maps
  Discord channel ids to `{name, dir}`. Your message in `#ghpr` goes to
  worker `ghpr` in that repo; the worker's reply comes back to `#ghpr`.
- **Push-first: the worker is the publisher.** Every worker starts with an
  injected system-prompt protocol: message Ned via `discord-notify` ONLY
  when the task is complete, it is blocked on a question, or a check-in was
  requested — multi-hour tasks run silently with no per-turn chatter, and
  workers create/address other channels with `bridge-ctl` and
  `discord-notify -t` (tools, not screen reading).
- **Fallback replies are exact.** When a turn ends and the worker didn't
  message Ned itself, the bridge extracts the final assistant message
  verbatim from the session transcript (incremental byte-offset reads, so a
  pre-flush Stop hook yields a retry instead of the previous turn's reply),
  split at Discord's 2000-char limit, capped at 8k with a `!screen` hint.
- **Idle reaping + resume.** Workers idle longer than `idle_minutes`
  (default 45) are stopped. The next message revives the worker with
  `claude --continue`, restoring the conversation from Claude Code's own
  session history — never hundreds of instances, never lost context.
- **An orchestrator channel.** The worker named `orchestrator` (mapped like
  any repo, directory doesn't matter) gets an extra injected brief teaching
  it `bridge-ctl`/`claude-worker`/`agent-checkup`, so `#orchestrator` is a
  natural-language remote for the whole plane — "spin up a worker on ghpr
  and have it triage the failing tests" instead of bot commands. The `!`
  commands keep working everywhere.
- **Steering, not queueing.** Messages are delivered straight into the
  session even mid-turn (Claude Code natively treats typed-while-running
  input as steering); ⏳ marks delivered-while-busy, ✅ delivered-while-idle.
  Messages starting with `/` are sent as typed keystrokes so Claude Code
  slash commands execute. `!checkin` asks a running worker to post a 3-5
  line progress update and keep going.
- Only allowlisted Discord user ids are honored.

## Tools

- **`claude-bridge`** (desktop only) — the daemon. Discord commands
  (allowed users, any visible channel): `!status`, `!checkin [name]`,
  `!model <model> [name]` (typed `/model`), `!clear [name]` (fresh context —
  restarts the worker *without* `--continue`, the deterministic wipe),
  `!compact [name]` (typed `/compact`), `!stop [name]`, `!restart [name]`,
  `!screen [name]`, `!addrepo <name> <path>` (creates `#<name>` under the
  Claude category and saves the mapping). Any message starting with `/` is
  typed into the worker as keystrokes, so every Claude Code slash command
  works from Discord (e.g. `/compact focus on the PR work`). Localhost event
  listener on `127.0.0.1:8765` (HMAC-signed `X-Webhook-Signature`).
- **`bridge-ctl`** (desktop only) — the tools-based bridge interface for
  workers and shells: `bridge-ctl addrepo <name> <path>` creates and maps a
  repo channel via a signed event (returns the channel id);
  `bridge-ctl start <name>` starts that repo's worker through the bridge
  (protocol injected, `--continue` resume — what the orchestrator uses);
  `bridge-ctl repos` lists mappings.
- **`claude-worker`** (desktop only) — worker lifecycle:
  ```sh
  claude-worker start impl --dir ~/projects/ghpr --chat discord:<channel>
  claude-worker send impl "run the test suite"     # '-' reads stdin
  claude-worker wait impl --for DONE --timeout 900 # synchronous use
  claude-worker read impl 120 / list / status / restart / stop
  ```
  `start` blocks until the worker is ready and auto-accepts the folder-trust
  dialog; `send` verifies submission (retries Enter while the input box
  still holds the text, `--type` sends literal keystrokes for slash
  commands); `--chat` records the repo channel and opts the worker into
  push-on-done.
- **`claude-worker-done-relay`** — Stop hook; signed `turn_ended` event
  (with the transcript path) to the bridge when a chat-bound worker ends a
  turn.
- **`claude-worker-todo-relay`** — PostToolUse hook on
  `TodoWrite|TaskCreate|TaskUpdate`; posts the live checklist to the repo
  channel via the bridge (webhook fallback to the main channel).
- **`discord-notify`** — one-shot message from any shell/Claude session;
  workers default to their own repo channel. `-i <file>` attaches images/files
  (repeatable); `--help` prints usage without sending.
- **`claude-launch`** (shared, all hosts) — interactive remote-control
  launcher behind `cl` and all workers; strips `ANTHROPIC_API_KEY`/Bedrock/
  Vertex variables so nothing can push a session onto API billing.
- **`agent-checkup`** (desktop only) — PASS/WARN/FAIL readiness report.

## State, config, secrets

- Worker state: `~/.local/state/claude-workers/<name>/` (`meta` key=value,
  `output.log` from pipe-pane, relay dedupe hash). No secrets.
- Bridge config: `~/.config/claude-bridge/config.json` (`category_id`,
  `allowed_users`, `idle_minutes`, `listen_port`, `repos`).
- Secrets (all chmod 600, never in env or logs):
  `~/.config/claude-workers/discord-bot-token` (bot token),
  `~/.config/claude-workers/bridge-webhook` (listener URL + HMAC secret),
  `~/.config/claude-workers/discord-webhook` (fallback channel webhook).

## Hooks (in `~/.claude/settings.json`)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "TodoWrite|TaskCreate|TaskUpdate",
        "hooks": [{ "type": "command", "command": "claude-worker-todo-relay" }]
      }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "claude-worker-done-relay" }] }
    ]
  }
}
```

## Setup / first smoke test

1. `pip3 install --user discord.py`; bot needs Message Content +
   Manage Channels in the Discord developer portal.
2. `./scripts/link.sh`, then `systemctl --user enable --now claude-bridge`
   (linger should be on: `loginctl enable-linger $USER`).
3. `agent-checkup` — fix anything red.
4. In Discord: `!addrepo scratch /tmp`, then message `#scratch`
   ("reply with the word ready"). Expect 🚀/✅ reactions, the reply posted
   back, and `💤` after the idle window.

## Operating rules

- Workers run on the interactive Claude subscription only — no `claude -p`,
  no API keys, no provider configs.
- Workers don't push or edit main/master directly unless explicitly asked;
  work lands on branches/PRs.
- The bridge never interprets content; if routing logic needs "judgment,"
  that judgment belongs in the worker's prompt, not the bridge.
