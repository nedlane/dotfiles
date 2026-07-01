# Splitting the agent control plane into `agent-bridge` (submodule)

## Goal

The Claude-worker control plane (Discord↔worker bridge, worker lifecycle,
capability profiles, relays, skills) has outgrown living inline under
`hosts/wsl-desktop/`. Extract it into a standalone repo **`nedlane/agent-bridge`**
(private) and reference it back into dotfiles as a **git submodule** mounted at
`hosts/wsl-desktop/agent-bridge/`, preserving the files' commit history.

## Scope

**Moves into `agent-bridge`** (with history via `git filter-repo`):

| dotfiles path | new-repo path |
|---|---|
| `hosts/wsl-desktop/bin/` (8 scripts) | `bin/` |
| `hosts/wsl-desktop/claude-profiles/` | `claude-profiles/` |
| `hosts/wsl-desktop/claude/skills/{claude-bridge,discord-notify}/` | `skills/` |
| `hosts/wsl-desktop/systemd/claude-bridge.service` | `systemd/claude-bridge.service` |

`bin/`: claude-bridge, claude-worker, discord-notify, bridge-ctl,
claude-worker-todo-relay, claude-worker-done-relay, agent-checkup, term-shot.

**Stays in dotfiles** (per Ned): `hosts/wsl-desktop/host.zsh`, `host.tmux`
(genuine WSL2 overlay), and `hosts/wsl-desktop/claude/CLAUDE.md` (the `ghpr`
host overlay, consumed by `link.sh`'s `generate_claude_md()` — not control-plane
logic).

The subsystem's **smoke tests stay in dotfiles** (`tests/*-smoke.sh`) as
integration tests, because they depend on `shared/bin/claude-launch` which stays
in dotfiles; only their internal paths are re-pointed at the submodule. The new
repo gets its own lightweight CI (shellcheck + `py_compile`).

## Decisions (confirmed with Ned)

- Name: **`agent-bridge`**; visibility: **private**; mechanism: **git submodule**.
- History: preserved with `git filter-repo` (paths span 4 non-shared prefixes,
  so `subtree split` on a single prefix won't do).
- `PROFILE_DIR` in `bin/claude-bridge` becomes **self-locating**
  (`../claude-profiles` relative to `realpath(__file__)`), keeping the
  `CLAUDE_PROFILES_DIR` env override. This removes the old `DOTFILES_DIR` +
  hardcoded `hosts/wsl-desktop/claude-profiles` coupling so the repo is
  mount-agnostic.

## Wiring re-pointed in dotfiles

1. `scripts/link.sh`: bin glob (~149), skills loop (~154), systemd unit (~158)
   → `hosts/wsl-desktop/agent-bridge/{bin,skills,systemd}/…`.
   `generate_claude_md` overlay path is **unchanged** (CLAUDE.md stays).
2. `tests/`: `link-smoke.sh` link-target asserts, `repository-smoke.sh` bin glob,
   and each subsystem smoke's `$ROOT/hosts/wsl-desktop/bin/…` → `…/agent-bridge/bin/…`.
3. `.github/workflows/ci.yml`: shellcheck bin glob (45), `py_compile` path (99)
   → submodule paths; add `submodules: recursive` to the `repository` and
   `link-platforms` checkout steps (link.sh skips linking when the source file
   is absent, so the smokes need the submodule content checked out).
4. `README.md` (~97, ~119) and `docs/agent-control-plane.md` (~18): note the
   submodule and update paths. Dated `docs/superpowers/specs|plans/*` are left
   as historical records.

## Execution order (keeps the running bridge + live symlinks valid throughout)

1. Build `agent-bridge` from a fresh local clone via `filter-repo` (+ renames);
   apply the self-locating `PROFILE_DIR` edit; add `README.md` + CI; commit.
2. `gh repo create nedlane/agent-bridge --private`; push `main`.
3. In dotfiles: `git submodule add` the repo at `hosts/wsl-desktop/agent-bridge/`
   (new files now on disk alongside the old ones).
4. Edit link.sh / tests / ci.yml / README / docs to the new paths.
5. Re-run `./scripts/link.sh` → symlinks retarget old→new (both exist, no
   "skip (no source)"); every `~/.local/bin` symlink stays valid.
6. `git rm` the old `hosts/wsl-desktop/{bin,claude-profiles,claude/skills,systemd/claude-bridge.service}`;
   symlinks already point at the submodule, so nothing dangles.
7. Verify: `systemctl --user status claude-bridge` still `active (running)`;
   `readlink` every relinked symlink resolves into the submodule; run the
   subsystem smokes. **Do not restart the service** — ExecStart uses the stable
   `~/.local/bin/claude-bridge` symlink and the unit file is byte-identical, so
   `daemon-reload` alone (no restart) suffices.
8. Commit dotfiles (submodule pointer + `.gitmodules` + rewiring).

## Risks

- The live bridge holds its source in memory; moving files on disk won't kill it.
  The relink-before-`git rm` ordering means `discord-notify` and the relays
  (invoked as hooks) never see a dangling symlink.
- CI: submodule content must be checked out for the smokes and link-smoke to
  pass — handled by `submodules: recursive`.
