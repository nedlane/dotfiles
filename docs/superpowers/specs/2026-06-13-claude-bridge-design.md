# claude-bridge — Discord ↔ Claude Code worker bridge

Replaces the Hermes gateway. No LLM in the routing path: Discord repo
channels map 1:1 to tmux-backed interactive Claude Code workers; the bridge
is a deterministic pipe. Claude Code (on the Claude subscription) is the only
intelligence in the loop.

## Decisions (agreed 2026-06-13)

- **Channel-per-repo, no threads.** Channels live under the Discord category
  `Claude` (id `1515015058009231370`). The bot has Manage Channels and
  creates repo channels itself via `!addrepo`.
- **One worker per repo.** All messages in `#ghpr` go to worker `ghpr`.
- **Idle reaping + resume.** Workers idle longer than `idle_minutes`
  (default 45) are stopped; the next channel message revives them with
  `claude --continue`, restoring the conversation from Claude's own session
  history. Never hundreds of instances.
- **Reuse the existing bot token** (`~/.config/claude-workers/discord-bot-token`).
- Only `allowed_users` (Ned: 656356624965042180) are honored.

## Components

1. **`hosts/wsl-desktop/bin/claude-bridge`** — Python 3 daemon (discord.py,
   stdlib otherwise; `discord` imported only at runtime so helpers stay
   import-safe for tests).
   - Config `~/.config/claude-bridge/config.json`: `category_id`,
     `allowed_users`, `idle_minutes`, `listen_port` (default 8765),
     `repos: {channel_id: {name, dir}}`.
   - **In:** message in a repo channel → ensure worker
     (`claude-worker start <name> --dir <dir> --chat discord:<channel>`,
     plus `-- --continue` when reviving) → `claude-worker send`. If the
     worker is mid-turn, react ⏳ and queue; deliver on the next
     `turn_ended`.
   - **Out:** localhost HTTP listener (`127.0.0.1:<listen_port>`), HMAC-SHA256
     via `X-Webhook-Signature` (secret in
     `~/.config/claude-workers/bridge-webhook`). `POST /event`:
     - `turn_ended` (from the Stop hook): extract the worker's final reply
       from `transcript_path`, split at 2000 chars, post to the repo channel,
       then flush one queued message.
     - `send` (from todo relay / discord-notify): post `content` to the
       channel in `chat` (or the first repo channel as fallback).
   - **Reaper:** background task stops workers idle > `idle_minutes`.
   - **Commands** (allowed users, any visible channel):
     `!status`, `!stop [name]`, `!restart [name]`, `!screen [name]`,
     `!addrepo <name> <path>` (creates the channel under the category, saves
     the mapping; path must exist).

2. **`claude-worker-done-relay`** (rework): config file renamed to
   `bridge-webhook` (`BRIDGE_WEBHOOK_URL` / `BRIDGE_WEBHOOK_SECRET`); payload
   gains `session_id` and `transcript_path` so the bridge can extract exact
   reply text.

3. **`claude-worker-todo-relay` / `discord-notify`** (rework): the
   thread/channel path posts a signed `send` event to the bridge instead of
   `hermes send`; Discord webhook fallback (main channel) unchanged.

4. **Hermes excision:** delete `hosts/wsl-desktop/hermes/`, its linker entry
   and link-smoke assert, and the hermes checks in `agent-checkup` (replaced
   by bridge checks: tool linked, config + secret files, port listening,
   discord.py importable). New Claude skill `claude-bridge` documents
   `!addrepo` and channel setup so Claude can do it on request.

5. **Service:** `hosts/wsl-desktop/systemd/claude-bridge.service`, linked to
   `~/.config/systemd/user/`, `Restart=on-failure`; linger is already on.

## Error handling

- Bridge never forwards messages from non-allowed users; unknown channels
  are ignored except `!`-commands.
- Worker dead/start failure → error reply in the channel, not silence.
- Replies > 2000 chars split on line boundaries; > 8000 chars truncated with
  a note to use `!screen`.
- All relay scripts stay exit-0 (hooks must never break a Claude session).

## Testing

- `tests/claude-bridge-smoke.sh`: imports the bridge's pure helpers
  (command parsing, transcript extraction, message splitting, HMAC verify,
  config round-trip) with python3 — no Discord, no network.
- Existing relay/notify smoke tests updated for the bridge endpoint.
- CI shellcheck loop taught to skip python files in `hosts/wsl-desktop/bin`.
