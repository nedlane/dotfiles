# Claude Worker Control Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Orchestration-safe standalone scripts so Codex (planner) can run persistent tmux-backed interactive Claude Code workers on the subscription auth path, plus a readiness check and docs.

**Architecture:** `Discord/OpenClaw/Hermes → Codex → claude-worker → tmux → claude-launch → interactive Claude Code`. `claude-launch` lives in `shared/bin/` (the shared `cl` function delegates to it on every host); the control plane proper — `claude-worker` (lifecycle manager over tmux sessions named `cw-<name>`, Claude titles `"<host> / worker:<name>"` so orchestrated sessions are distinguishable from manual `cl` sessions), `claude-worker-todo-relay` (PostToolUse/TodoWrite hook posting live task checkboxes to a Discord webhook with zero model tokens), and `agent-checkup` (readiness/auth-mode report) — is desktop-only in `hosts/wsl-desktop/bin/`, linked only for the `wsl-desktop` host (mid-implementation user direction; same pattern as `hosts/mac/bin`). Worker state lives in `${XDG_STATE_HOME:-~/.local/state}/claude-workers/<name>/` as flat `meta` key=value files plus `output.log` from `tmux pipe-pane`.

**Tech Stack:** bash, tmux, existing dotfiles linker/tests/CI conventions.

**Naming contract (per user):** manual `cl` sessions keep `"<host> / <dir>"` titles; orchestrated workers use `"<host> / worker:<name>"` titles and `cw-<name>` tmux sessions so Codex can track them separately.

---

### Task 1: `claude-launch` standalone launcher + `cl` delegation

**Files:**
- Create: `shared/bin/claude-launch` (executable)
- Modify: `shared/zsh/aliases.zsh` (cl function body)
- Create: `tests/claude-launch-smoke.sh` (executable)
- Modify: `tests/cl-wrapper-smoke.sh` (stub `claude` via PATH instead of zsh function)
- Modify: `.github/workflows/ci.yml` (add smoke step)
- Modify: `tests/link-smoke.sh` (assert new bin link)

- [x] **Step 1: Write failing test** `tests/claude-launch-smoke.sh` — stubs `claude` on PATH (records argv + `ANTHROPIC_API_KEY` visibility), asserts: default title `desktop / <dir>` for `wsl-desktop`; `--label worker:impl` title; explicit `--name`/`-n` wins with no injected title; passthrough args; host fallback from `$XDG_CONFIG_HOME/dotfiles/host` when `DOTFILES_HOST` unset; forbidden env vars stripped.
- [x] **Step 2: Run it; expect FAIL** (`claude-launch: command not found`).
- [x] **Step 3: Implement `shared/bin/claude-launch`** — strip `ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_BEDROCK_BASE_URL ANTHROPIC_VERTEX_PROJECT_ID CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX AWS_BEARER_TOKEN_BEDROCK`; map `DOTFILES_HOST` (env, falling back to the recorded host file) to curated device names exactly as `cl` does; extract `--label`; explicit `--name`/`-n` short-circuits; `exec claude --dangerously-skip-permissions --remote-control [--name "<host> / <label|dirbase>"] args…`.
- [x] **Step 4: Re-point `cl`** in `shared/zsh/aliases.zsh` to `"${DOTFILES_DIR:-$HOME/dotfiles}/shared/bin/claude-launch" "$@"`; rework `tests/cl-wrapper-smoke.sh` to stub `claude` as a PATH executable.
- [x] **Step 5: Run both smoke tests; expect PASS.** Add CI step + link-smoke assert.
- [x] **Step 6: Commit.**

### Task 2: `claude-worker` lifecycle manager (+ Discord todo relay)

**Files:**
- Create: `hosts/wsl-desktop/bin/claude-worker` (executable)
- Create: `hosts/wsl-desktop/bin/claude-worker-todo-relay` (executable)
- Create: `tests/claude-worker-smoke.sh`, `tests/claude-worker-todo-relay-smoke.sh` (executable)
- Modify: `scripts/link.sh` (wsl-desktop-only bin section), `.github/workflows/ci.yml`, `tests/link-smoke.sh`, `tests/repository-smoke.sh`

- [x] **Step 1: Write failing test** — stub `tmux` (records argv to `$TMUX_STUB_LOG`; `has-session` succeeds iff `$TMUX_STUB_ALIVE` file exists; `load-buffer` drains stdin) and stub `claude`. With `CLAUDE_WORKERS_STATE` pointed at a temp dir and `CLAUDE_WORKER_SEND_DELAY=0`, assert: `start impl --dir <proj>` constructs `new-session -d -s cw-impl -c <proj>` with `--label worker:impl`, starts `pipe-pane`, writes `meta`; double-start fails while alive; invalid names rejected; `send` does bracketed `paste-buffer -p` then `send-keys … Enter`; `read` uses `capture-pane -p`; `stop` kills `=cw-impl`; `restart` reuses the recorded dir; `list` runs.
- [x] **Step 2: Run it; expect FAIL.**
- [x] **Step 3: Implement `shared/bin/claude-worker`** with subcommands `start|send|read|list|status|stop|restart`, state dir convention, exact-match `-t "=cw-<name>"` targeting, `printf '%q '`-quoted launch command, name validation `^[A-Za-z0-9][A-Za-z0-9_-]*$`.
- [x] **Step 4: Run test; expect PASS.** Add CI step + link-smoke assert.
- [x] **Step 5: Commit.**

### Task 3: `agent-checkup` readiness check

**Files:**
- Create: `hosts/wsl-desktop/bin/agent-checkup` (executable)
- Create: `tests/agent-checkup-smoke.sh` (executable)
- Modify: `.github/workflows/ci.yml`, `tests/link-smoke.sh`

- [x] **Step 1: Write failing test** — fake `$HOME` with stub `codex`/`claude`/`tmux`; `~/.codex/auth.json` with `auth_mode: chatgpt`; `~/.claude/.credentials.json` present. Assert exit 0 + PASS markers; `ANTHROPIC_API_KEY` set ⇒ WARN; missing `codex` ⇒ FAIL exit 1; no secret values echoed.
- [x] **Step 2: Run it; expect FAIL.**
- [x] **Step 3: Implement** checks: tmux present; claude present + interactive OAuth creds (`~/.claude/.credentials.json` or `oauthAccount` in `~/.claude.json`); codex present + `auth_mode` in `~/.codex/auth.json` (chatgpt ⇒ PASS, apikey ⇒ WARN, missing ⇒ FAIL with `codex login` hint); forbidden Anthropic/provider env vars ⇒ WARN (claude-launch strips them); `OPENAI_API_KEY` env ⇒ WARN; worker scripts resolvable on PATH; state root writable; print manual-check list for Discord/OpenClaw/Hermes + subscription verification. Aggregate, exit 1 on any FAIL.
- [x] **Step 4: Run test; expect PASS.** Add CI step + link-smoke assert.
- [x] **Step 5: Commit.**

### Task 4: Documentation

**Files:**
- Create: `docs/agent-control-plane.md`
- Modify: `README.md` (short pointer section)

- [x] **Step 1: Write `docs/agent-control-plane.md`** — architecture diagram, naming contract, tool reference, state/log conventions, manual Discord/OpenClaw/Hermes steps, subscription-path verification for both CLIs, first smoke test, operating rules (Codex plans/schedules/summarises; Claude workers implement/review/test; no API/provider routes; no direct pushes/main-branch edits unless asked).
- [x] **Step 2: README pointer.**
- [x] **Step 3: Run full test suite; commit.**
