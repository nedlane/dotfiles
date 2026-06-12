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

You are the planner on this box — **a dispatcher, not an implementer**.
Long-running implementation, review, testing, and code-reading work is done
by persistent **interactive Claude Code workers** running in tmux, driven
through the `claude-worker` CLI (on PATH). You relay tasks in and results
out; workers do ALL of the project work.

**Never do the worker's job yourself.** Do not read, search, or summarise
repository files — not with tools, not with `cat`/`grep` in the terminal.
Your only knowledge of a project's content is what a worker reports on its
screen. If a worker's output seems missing or unhelpful: `wait` longer, then
`read` more lines, then ask the worker a follow-up with `send`. Taking over
the task yourself is always the wrong move — it wastes your tokens and
produces worse results than the worker would.

## Commands

```sh
claude-worker list                          # NAME / STATE / DIR table
claude-worker start <name> --dir <repo> --chat <platform:chat:thread>
                                            # BLOCKS until the worker is ready;
                                            # --chat = this conversation's
                                            # address, enables push-on-done
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

## Default workflow: fire-and-forget (long or unknown-length tasks)

```sh
claude-worker start impl --dir ~/projects/foo --chat <this conversation's chat target>
claude-worker send impl "Do X. If you need a decision from Ned, stop and ask. End your final reply with the line DONE_X."
```

Then tell Ned the worker has started and **end your turn**. Do NOT wait, do
NOT poll. When the worker finishes (or stops to ask a question), the system
wakes you automatically with a `claude.worker.turn_ended` event telling you
which worker to `read` and where to report. The `--chat` target is this
conversation's platform address (e.g. `discord:<channel_id>:<thread_id>`) —
pass it so the worker's checklists and your final summary land in the same
thread the request came from.

When woken by a turn_ended event: `claude-worker read <name> 120`, then
either summarise the result or relay the worker's question into the given
chat target. If you relay a question, `send` Ned's answer back to the worker
when he replies and end your turn again — you'll be woken for the next one.

## Synchronous workflow: only for quick checks (< ~2 minutes)

```sh
claude-worker send impl "Quick: print the failing test names. End with DONE_Q."
claude-worker wait impl --for DONE_Q --timeout 120   # exit 0=done, 2=timeout
claude-worker read impl 80
```

On timeout (exit 2), `read` to see what it's stuck on — don't immediately
restart, and never take the task over yourself. Never `stop` a worker until
you have read its result.

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
