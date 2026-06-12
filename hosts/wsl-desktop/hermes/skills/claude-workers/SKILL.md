---
name: claude-workers
description: "Orchestrate persistent interactive Claude Code workers in tmux via claude-worker (start/send/read/list/status/restart/stop)."
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [claude, claude-code, worker, tmux, orchestration, codex, implement, review, test]
    related_skills: [devops]
---

# Claude Code Workers

You are the planner on this box. Long-running implementation, review, and
testing work is done by persistent **interactive Claude Code workers** running
in tmux, driven through the `claude-worker` CLI (on PATH). You plan, schedule,
and summarise; workers do the code work.

## Commands

```sh
claude-worker list                          # NAME / STATE / DIR table
claude-worker start <name> --dir <repo>     # BLOCKS until the worker is ready
claude-worker send <name> "<message>"       # paste + submit ('-' = stdin)
claude-worker wait <name> --for TEXT --timeout 900
                                            # block until TEXT appears on the
                                            # worker's screen (omit --for to
                                            # wait until idle at the prompt)
claude-worker read <name> [lines]           # capture the worker's screen
claude-worker status <name>                 # meta + running yes/no
claude-worker restart <name>                # same name, same recorded dir
claude-worker stop <name>
```

Worker names are roles: `impl`, `reviewer`, `tester` (one role per worker;
pick the repo per task with `--dir`). tmux sessions are `cw-<name>`; Claude
session titles are `<host> / worker:<name>`. State and logs live in
`~/.local/state/claude-workers/<name>/` (`meta` is flat key=value).

## The one true workflow

```sh
claude-worker start impl --dir ~/projects/foo        # returns "state: ready"
claude-worker send impl "Do X. End your reply with the line DONE_X."
claude-worker wait impl --for DONE_X --timeout 900   # exit 0=done, 2=timeout
claude-worker read impl 80                           # collect the result
```

Always give the worker an explicit end-marker line (like `DONE_X`) and wait
for it with `wait --for`. On timeout (exit 2), `read` to see what it's stuck
on — don't immediately restart.

## Operating rules

- **Use only the commands above to interact with workers.** Never call tmux
  directly (`send-keys`, `capture-pane`, ...), never write polling or monitor
  scripts, never spawn background watcher processes — `claude-worker wait`
  is the supported way to wait. If the tooling seems insufficient, say so
  instead of improvising around it.
- `start` already handles the folder-trust dialog and blocks until the worker
  is ready; don't pre-poke new workers with empty sends or raw Enters.
- One `send` per task, then `wait` — Claude Code tasks can take minutes;
  don't spam messages into a busy worker.
- Workers run on the interactive Claude subscription. **Never** start Claude
  via API keys, `claude -p`, OpenRouter, or provider configs, and never set
  `ANTHROPIC_API_KEY`-style variables.
- Workers must not push or edit main/master directly unless the human
  explicitly asked; work lands on branches/PRs.
- Workers' task checkboxes auto-post to Discord via a separate hook — don't
  re-paste their todo lists, just summarise outcomes.
- If a worker is wedged (no prompt, garbage screen), `claude-worker restart
  <name>` and re-send the task with a short recap.
