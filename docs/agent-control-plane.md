# Local agent control plane

Desktop-only setup that lets Discord/OpenClaw/Hermes drive Codex as a
planner, while Codex orchestrates persistent **interactive** Claude Code
workers in tmux. Both sides run on subscriptions: Codex on the ChatGPT
plan (OAuth), Claude Code on the Claude plan via its normal interactive
login. No Anthropic API keys, no OpenRouter, no provider billing, anywhere.

```
Discord / OpenClaw / Hermes        (chat front-end; you configure this)
            │
            ▼
        Codex CLI                  (planner/scheduler; ChatGPT subscription)
            │  shell calls
            ▼
     claude-worker …               (hosts/wsl-desktop/bin, desktop-only)
            │  tmux sessions cw-<name>
            ▼
      claude-launch                (shared/bin, used by `cl` everywhere)
            │
            ▼
  interactive Claude Code          (Claude subscription, remote-control mode)
            │  PostToolUse hook on TodoWrite
            ▼
 claude-worker-todo-relay ──────▶  Discord webhook (live task checkboxes,
                                    zero Codex/model tokens)
```

## Naming contract

| Kind | tmux session | Claude session title |
|---|---|---|
| Manual `cl` session | (wherever you ran it) | `<host> / <dir>` |
| Orchestrated worker | `cw-<name>` | `<host> / worker:<name>` |

Manual sessions keep the directory-based titles; workers are always
`worker:<name>`, so Codex (and the claude.ai session list) can track them
without colliding with sessions you start by hand. Worker names are free-form
(`impl`, `reviewer`, `tester`, `ghpr-impl`, …) — nothing is tied to one repo.

## Tools

- **`claude-launch`** (`shared/bin`, all hosts) — standalone launcher for
  interactive remote-control Claude Code; `cl` delegates to it. Resolves the
  host prefix from `$DOTFILES_HOST` or the linker's recorded host file, so it
  works from non-interactive shells. Strips `ANTHROPIC_API_KEY`,
  `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, Bedrock/Vertex variables
  before starting, so a calling environment can never flip a session onto
  API billing.
- **`claude-worker`** (desktop only) — worker lifecycle:
  ```sh
  claude-worker start impl --dir ~/projects/ghpr   # detached tmux worker
  claude-worker send impl "run the test suite"     # '-' reads stdin
  claude-worker read impl 120                      # capture the screen
  claude-worker list / status impl
  claude-worker restart impl / stop impl
  ```
- **`claude-worker-todo-relay`** (desktop only) — Claude Code hook that posts
  each worker's live checklist (TodoWrite todos and TaskCreate/TaskUpdate
  task lists) to a Discord webhook. Pure parse + POST: no Codex, no model
  calls, no tokens. Only fires in sessions started by
  `claude-worker` (they carry `CLAUDE_WORKER=<name>`); manual sessions stay
  quiet. Deduped, capped to Discord's message size, always exits 0 so a relay
  problem can never break a session.
- **`agent-checkup`** (desktop only) — readiness report (PASS/WARN/FAIL plus
  a manual-checks list). Run it after linking and whenever something feels
  off; exits 1 if anything hard-fails.

## State and logs

Per-worker state lives in `~/.local/state/claude-workers/<name>/`
(`$CLAUDE_WORKERS_STATE` overrides; no secrets stored):

- `meta` — flat `key=value`: `name`, `session`, `dir`, `label`, `created`,
  `log`. Orchestrators should read these files instead of shell state.
- `output.log` — append-only raw terminal output (`tmux pipe-pane`). It
  captures whatever the worker prints, so don't paste secrets into workers.
- `todo-relay.last` — dedupe hash for the Discord relay.

The Discord webhook URL lives in `~/.config/claude-workers/discord-webhook`
(`chmod 600`), never in env vars, logs, or this repo.

## Manual setup (one-time)

1. **Subscriptions/auth** — `codex login` with ChatGPT; run `claude` once and
   `/login` with the Claude subscription. Then run `agent-checkup`.
2. **Discord relay** — create a channel webhook (channel settings →
   Integrations → Webhooks), then:
   ```sh
   mkdir -p ~/.config/claude-workers
   printf '%s\n' '<webhook url>' > ~/.config/claude-workers/discord-webhook
   chmod 600 ~/.config/claude-workers/discord-webhook
   ```
3. **Todo-relay hook** — add to `~/.claude/settings.json` (merge with any
   existing hooks):
   ```json
   {
     "hooks": {
       "PostToolUse": [
         {
           "matcher": "TodoWrite|TaskCreate|TaskUpdate",
           "hooks": [{ "type": "command", "command": "claude-worker-todo-relay" }]
         }
       ]
     }
   }
   ```
   `TodoWrite` carries the whole checklist; for the task tools the relay
   re-reads `~/.claude/tasks/<session-id>/` so creates, edits, completions,
   and deletions all re-post the full list.
4. **Discord/OpenClaw/Hermes → Codex** — configure your bridge so Discord
   messages reach Codex on this machine (OpenClaw/Hermes setup is outside
   this repo). The only contract Codex needs: plan with its own tools, and
   drive workers exclusively through `claude-worker …` shell calls.

## Verifying the subscription paths

- **Codex:** `codex login status` should show a ChatGPT login;
  `agent-checkup` PASSes when `~/.codex/auth.json` has `auth_mode: chatgpt`.
  `OPENAI_API_KEY` should not be set in the environment.
- **Claude Code:** inside any worker (`tmux attach -t cw-<name>`) run
  `/status` — the account should be your Claude subscription, not an API key.
  `claude-launch` warns on stderr if it had to strip a forbidden variable.

## First smoke test

```sh
agent-checkup
claude-worker start scratch --dir /tmp
claude-worker send scratch "Reply with the word ready, then use TodoWrite to plan: say hi, say bye"
sleep 20 && claude-worker read scratch 60     # expect "ready" + a todo list
# the todo checkboxes should also appear in the Discord channel
claude-worker stop scratch
```

## Operating rules

- Codex plans, schedules, and summarises; Claude Code workers implement,
  review, and test. Codex never edits code directly in this setup.
- Workers run on the interactive subscription path only — no `claude -p`
  pipelines, no API keys, no provider configs, no OpenRouter.
- Workers don't push or edit main/master directly unless explicitly asked;
  work lands on branches/PRs.
- One worker per role (`impl`, `reviewer`, `tester`); pick the repo per task
  with `--dir`. Restart a wedged worker with `claude-worker restart <name>`.
