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
claude-worker start <name> --dir <repo>     # new detached worker in <repo>
claude-worker send <name> "<message>"       # type into the worker ('-' = stdin)
claude-worker read <name> [lines]           # capture the worker's screen
claude-worker status <name>                 # meta + running yes/no
claude-worker restart <name>                # same name, same recorded dir
claude-worker stop <name>
```

Worker names are roles: `impl`, `reviewer`, `tester` (one role per worker;
pick the repo per task with `--dir`). tmux sessions are `cw-<name>`; Claude
session titles are `<host> / worker:<name>`. State and logs live in
`~/.local/state/claude-workers/<name>/` (`meta` is flat key=value).

## Operating rules

- **Always `read` before `send`** — confirm the worker is idle at its prompt,
  not mid-task or showing a dialog. After `send`, poll `read` to see progress;
  Claude Code tasks can take minutes, so don't spam messages.
- Workers run on the interactive Claude subscription. **Never** start Claude
  via API keys, `claude -p`, OpenRouter, or provider configs, and never set
  `ANTHROPIC_API_KEY`-style variables.
- Workers must not push or edit main/master directly unless the human
  explicitly asked; work lands on branches/PRs.
- Workers' task checkboxes auto-post to Discord via a separate hook — don't
  re-paste their todo lists, just summarise outcomes.
- If a worker is wedged (no prompt, garbage screen), `claude-worker restart
  <name>` and re-send the task with a short recap.
