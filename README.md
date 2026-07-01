# dotfiles

Multi-host shell, tmux, Neovim, Git, and terminal configuration. Shared config
lives in `shared/`; each machine adds a small overlay from `hosts/<name>/`.
Host-specific prompt and tmux colors make the active machine obvious.

| Host | Type | tmux prefix | Accent | Profile |
|---|---|---|---|---|
| `mac` | macOS laptop | `C-Space` | blue | full |
| `wsl-desktop` | WSL2 desktop | `C-a` | mauve | full |
| `minipc` | homelab Linux | `C-b` | green | minimal |
| `minipc2` | homelab Linux | `C-b` | teal | minimal |
| `pi` | Raspberry Pi | `C-b` | red | minimal |

The full profile links the shared Git defaults. Identity and signing settings remain private in
`~/.config/dotfiles/gitconfig.local`. The minimal profile skips the shared Git
config so homelab machines without a signing key can still commit normally.
Override automatic selection with `DOTFILES_PROFILE=full` or
`DOTFILES_PROFILE=minimal`.

## Install

Clone the repository to the default location:

```sh
git clone https://github.com/nedlane/dotfiles ~/dotfiles
cd ~/dotfiles
```

Bootstrap the current machine:

```sh
./scripts/setup.sh
```

The setup script uses the same host detection as the linker:

- macOS selects `mac` and installs packages with Homebrew.
- WSL2 selects `wsl-desktop` and installs packages with apt.
- Other Linux machines use their short hostname and the no-sudo homelab setup.

Explicitly select a host when detection is not sufficient:

```sh
./scripts/setup.sh minipc
```

Homelab setup is per-user and requires `zsh`, `tmux`, `git`, and `curl` to
already be installed. A C compiler (`cc`/`gcc`/`clang`) is recommended — the
nvim-treesitter rewrite compiles parsers with it; setup warns loudly if none is
found. It installs Neovim, tree-sitter, ripgrep, fd, fzf, shell plugins, and TPM
under the user's home directory, then enables a persistent `main` tmux session
with a systemd user service.

To only refresh symlinks without installing anything:

```sh
./scripts/link.sh             # auto-detect the host
./scripts/link.sh minipc      # or explicitly select a host
```

The linker records the selected host in `~/.config/dotfiles/host`. Existing
files in the way are moved to a timestamped `~/dotfiles-pre-link-backup-*`
directory; they are never deleted.

For a full-profile machine, create the private Git identity include after the
first link:

```sh
mkdir -p ~/.config/dotfiles
cp shared/git/gitconfig.local.example ~/.config/dotfiles/gitconfig.local
${EDITOR:-vi} ~/.config/dotfiles/gitconfig.local
```

This file is outside the repository and should contain your name, email, and
signing-key path.

Optionally enable a local pre-commit secret scan (catches a pasted token before
it ever leaves your machine; requires [gitleaks](https://github.com/gitleaks/gitleaks)):

```sh
git config core.hooksPath scripts/hooks
```

## tmux Session Switcher

Inside tmux, `<prefix> w` opens an fzf menu containing local sessions and
sessions from reachable Tailscale peers. Local sessions appear immediately;
peers are queried in parallel with a timeout.

- Selecting a local session switches to it directly.
- Selecting a remote session creates a local proxy session over Tailscale SSH.
- The proxy's outer status bar is hidden, leaving the remote machine's colored
  status bar visible.
- After every switch, detached proxy sessions are pruned immediately. The
  selected remote proxy remains because it is attached.
- `<prefix> W` opens tmux's local-only session tree as a network-free fallback.

Remote peers need Tailscale SSH, tmux, and a tailnet ACL that permits access.
Windows peers and offline peers are excluded.

## Agent Control Plane (desktop only)

The `agent-bridge` submodule (at `hosts/wsl-desktop/agent-bridge/`) carries a
Discord remote control for interactive Claude Code: `claude-bridge` maps repo
channels to persistent tmux workers (`claude-worker`), with hook-driven
reply/checklist relays and a readiness check (`agent-checkup`). No LLM in the
routing path. The shared `claude-launch` backs the `cl` shorthand on every host.

This is a **private, desktop-only personal component** — the submodule points at
a private repo, so a plain clone won't fetch it and nothing here depends on it.
`link.sh` and `setup.sh` skip it cleanly when it's absent; only the owner's
`wsl-desktop` box populates it. See
[docs/agent-control-plane.md](docs/agent-control-plane.md) for the design.

> **Heads up:** the `cl` shorthand launches Claude Code with
> `--dangerously-skip-permissions` by default (full-trust, frictionless). If you
> adopt these dotfiles, know that `cl` bypasses Claude Code's permission prompts
> unless you change `shared/bin/claude-launch`.

## Layout

```text
shared/
  bin/tmux-switch            local + Tailscale tmux session switcher
  git/gitconfig              shared Git config for full-profile hosts
  git/gitconfig.local.example
                              template for private identity and signing config
  nvim/                      lazy.nvim configuration
  systemd/user/              persistent homelab tmux service
  tmux/tmux.conf             shared tmux config and plugins
  zsh/                       shared shell config, environment, and aliases
  p10k.zsh                   shared Powerlevel10k prompt
hosts/
  mac/                       macOS shell, tmux, Alacritty, and helper commands
  wsl-desktop/               WSL2 shell and tmux overlay
    agent-bridge/            Discord↔worker control plane (git submodule)
  minipc/                    homelab overlays
  minipc2/
  pi/
scripts/
  lib/host.sh                shared host detection
  link.sh                    safe host detection and symlink management
  setup.sh                   detected macOS, WSL2, or homelab bootstrap
```

## Adding a Host

1. Create `hosts/<name>/host.zsh` and `hosts/<name>/host.tmux`.
2. Add any hostname mapping needed by `scripts/lib/host.sh`.
3. Run `./scripts/link.sh <name>`.

Unknown Linux machines default to their short hostname and use the minimal
profile.

## Publishing Safely

Run a full-history secret scan before publishing or pushing rewritten history:

```sh
gitleaks git --redact --log-opts='--all' .
```

The CI workflow repeats this scan on pushes and pull requests. Never place
credentials, private keys, tokens, or application-managed state in the
repository.

CI also validates Bash and Zsh syntax, ShellCheck, Lua syntax, the Neovim
lockfile and core configuration, tmux configuration loading, linker behavior on
Linux and macOS, switcher pruning behavior, executable modes, and workflow
syntax.

## License

[MIT](LICENSE)
