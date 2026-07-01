# Guest channels for the Discord↔Claude bridge

**Status:** approved design (2026-07-02)
**Author:** Ned + agent

## Problem

The bridge maps each Discord channel under the **Claude** category 1:1 to a
tmux Claude Code worker. Today authorization is a single global
`allowed_users` list (just Ned): a user is either fully trusted — able to talk
to *every* worker and operate the control plane — or ignored. There is no way
to let another person interact with *one* agent in *one* channel.

Ned wants to invite other people (friends/family, and collaborators on a
shared project) and give them **scoped** access: e.g. a friend can talk to a
calendar agent to add an event, or a collaborator can work alongside his agent
in one repo — without reaching the rest of the machine or his other channels.

Trust level: friends/family and per-project collaborators. The threat model is
**accidents and scope creep, not attackers.** (Hard OS-level isolation is a
future upgrade if strangers ever enter the picture.)

## Design overview

One new concept — a **channel profile** — ties together three enforcement
layers. Defense in depth: each layer independently prevents a guest from
reaching anything they weren't granted.

### Layer 1 — Discord visibility (roles + channel overwrites)

- `@everyone` is denied **View Channel** on every existing channel + category
  (already applied 2026-07-02). A newly invited guest sees nothing by default.
  (Safe because Ned is the server *owner* and the bot has *Administrator* —
  both bypass channel overwrites, so nothing hides from Ned and the bridge
  keeps posting.)
- One Discord role per guest-accessible channel (`g-<channel>`); a channel
  permission overwrite grants that role **View + Send** on exactly its channel.
  The guest is assigned the role. A guest may hold several roles.

### Layer 2 — Bridge authorization (per-channel allowlist)

- Config schema: each `repos[channel_id]` entry gains two optional fields:
  - `guests: [discord_user_id, …]` — who *besides the owner* may talk here.
  - `profile: "owner" | "utility" | "collab"` — capability bundle (default
    `owner`).
  - Global `allowed_users` stays = the owner (Ned), who can talk everywhere.
- `on_message` gate changes from *global* `allowed_users` membership to:
  **owner OR `author.id ∈ this channel's guests`.** A guest posting in a
  channel they're not listed on is ignored even if Discord is misconfigured.
- **All slash commands stay owner-only** (unchanged
  `interaction.user.id in allowed_users` check). Guests talk to the agent;
  they never operate the control plane (`/restart`, `/stop`, `/addrepo`, …).

### Layer 3 — Capability profiles (what a guest agent can DO)

A profile selects the `claude` launch flags (and an optional versioned
settings file) for a channel's worker. Enforced with real `claude` CLI flags,
verified present on this machine:

- **`utility`** (calendar-style, maximally locked):
  - `--tools ""` — **disables every built-in tool** (no Bash, Read, Edit,
    Write, WebFetch — none).
  - `--mcp-config <profile>.mcp.json --strict-mcp-config` — loads **only** the
    profile's MCP server(s), ignoring all other MCP config on the machine.
  - `--allowedTools "mcp__<server>"` — pre-approves those MCP tools so they run
    without a permission prompt (a guest can't answer TUI prompts over
    Discord).
  - Worker cwd = a throwaway dir (`~/guest-workspaces/<channel>`), so even a
    tool bug has nothing sensitive to touch.
  - Net: the agent has *only* the calendar MCP tools. Nowhere to wander.

- **`collab`** (shared repo):
  - Worker cwd = a **dedicated checkout** (`~/guest-workspaces/<channel>`), NOT
    Ned's primary tree. Blast radius = that one checkout.
  - Normal dev tools, but a profile settings file adds `permissions.deny`
    guardrails: no `Bash(sudo:*)`, no `Read`/`Edit` of `~/.ssh/**`,
    `~/.config/claude*/**`, `~/.config/claude-workers/**`,
    `~/.config/claude-bridge/**`, and the bridge/dotfiles bin dirs.
  - Because a guest can't approve TUI permission prompts, the collab worker
    runs in an auto-accept mode *within the checkout* — capability is the
    point; the deny guardrails + dedicated checkout are the containment.

- **`owner`** (default): today's behavior, full trust, primary tree,
  unchanged.

**Key constraint discovered:** a guest cannot answer interactive
tool-permission dialogs (those live in the TUI, not Discord). So every
guest-facing profile must run so that its *intended* tools don't prompt —
solved for `utility` by `--allowedTools`, for `collab` by auto-accept inside
the dedicated checkout.

## New tooling (`bridge-ctl`)

- `bridge-ctl addguest <channel> <discord_id> [--profile utility|collab]` —
  one command wires all three layers: create/assign the `g-<channel>` Discord
  role, set the channel View+Send overwrite, add the id to the channel's
  `guests`, and record the `profile`. Idempotent.
- `bridge-ctl guests` — list who can reach what (channel → guests, profile).

Discord mutations (role create/assign, channel overwrite) go through the
bridge's signed-event listener like `addrepo`, so `bridge-ctl` stays a thin
signed client and the bridge remains the sole writer of Discord state + config.

Profiles live under `hosts/wsl-desktop/claude-profiles/` in the dotfiles repo,
version-controlled: `<profile>.settings.json` (permission guardrails) and,
where relevant, `<profile>.mcp.json` (the restricted MCP set).

## Data flow

Guest posts in `#calendar` → Discord role grants Send → bridge `on_message`
→ gate `channel_allows(cfg, channel_id, author_id)` (owner? or id ∈ guests?)
→ deliver to the `calendar` worker, launched with the `utility` profile
(calendar MCP only, no built-in tools) → worker acts → Stop hook posts the
reply back to `#calendar`. The guest can neither see nor address any other
channel; the Discord overwrite and the bridge gate each independently block it.

## Testing (extend `tests/claude-bridge-smoke.sh` + `bridge-ctl-smoke.sh`)

Pure helpers, no network:
- `channel_allows`: false for a non-listed user on a channel; true for the
  owner on every channel; true for a listed guest on *their* channel only,
  false on another channel.
- `profile_args(profile, cwd)`: `utility` yields `--tools ""`,
  `--strict-mcp-config`, and an `--allowedTools mcp__…` entry; `collab` yields
  the dedicated-checkout cwd and the deny-guardrail settings file; `owner`
  yields today's argv unchanged.
- Config round-trip preserves `guests` and `profile`.
- `start_args` for a profiled channel injects the profile flags *and* still
  injects the Discord protocol.

## Out of scope (YAGNI)

- OS-level isolation (separate Unix user / container) — future upgrade for
  untrusted guests.
- Guest access to slash commands / the control plane.
- Non-Claude-Code deterministic responders (the "C" option) — `utility`
  already makes the agent effectively that tight.

## Open dependency

The calendar agent itself needs a **Google Calendar MCP server + Ned's Google
OAuth credentials** (his account, browser consent). The profile *machinery* is
independent and testable without it; wiring the actual calendar MCP is the
final step and requires Ned.
