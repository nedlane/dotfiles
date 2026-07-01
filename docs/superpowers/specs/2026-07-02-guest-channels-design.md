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

---

# Addendum (2026-07-02): public front door + view/edit access

Follow-on to the above, built and shipped the same day.

## #welcome — a public greeter

A single public channel `#welcome` (the only place `@everyone` may View+Send)
is mapped to a real Claude worker running the new **`greeter`** profile. It is
NOT a push-first Ned worker: it gets the `GREETER` brief instead of `PROTOCOL`,
converses in plain text (the Stop-hook relay posts its replies back), and its
job is to find out which project a visitor wants and file a request.

The greeter is tightly boxed: `greeter` profile = `--enforce-perms`
(permissions actually enforced — see below), `--strict-mcp-config` with an
empty `greeter.mcp.json` (no MCP), and `greeter.settings.json` that allows only
`Bash(bridge-ctl repos)` and `Bash(bridge-ctl request:*)`. Anything else stalls
on a permission prompt no visitor can answer. Its cwd is a throwaway
`~/guest-workspaces/welcome`. Inbound messages in #welcome are tagged with the
sender's name + Discord id so the greeter knows who to file for; a visitor's
leading `/` is never treated as a Claude Code command.

## Request → approval → grant

1. Greeter runs `bridge-ctl request <discord_id> <project> "<summary>"` →
   `claude.bridge.request` event.
2. The bridge posts an **approval card** to the private `#requests` channel with
   `👁️ view-only · ✏️ edit · ❌ deny` pre-added, embedding a
   `req:<id>:<project>` marker so the decision survives a restart (state lives
   in the message, not memory).
3. Owner reacts: `on_raw_reaction_add` (owner-only) parses the marker and calls
   `do_addguest(project, id, access)` — ✏️ → edit, 👁️ → view-only, ❌ →
   decline. The card is edited to show the outcome and its reactions cleared so
   it can't re-fire; the visitor is told the result back in #welcome.

## Access levels (view vs edit) + lockdown

Access is now a **per-member channel overwrite**, not a role: `edit` = View +
Send (drives the collab worker), `view` = View, Send denied (watches only).
Config tracks editors in `guests` and watchers in `viewers`, so the bridge gate
and Discord agree. Instant lockdown:

- `bridge-ctl viewonly <name>` / `viewonly --all` — drop editors to view-only.
- `bridge-ctl revoke <name> <id>` — remove someone entirely.
- `/lockdown` slash command — everyone everywhere to view-only, you untouched.

## Permission enforcement fix (important)

`claude-launch` launched every worker with `--dangerously-skip-permissions`,
which silently ignores all settings-file allow/deny rules. That would have made
the `greeter`/`collab` guardrails cosmetic. Fixed: `claude-launch` now takes
`--enforce-perms` to omit the bypass flag, and every guest profile
(`greeter`/`collab`/`utility`) passes it plus an explicit `--permission-mode`
so allow-listed tools run without a prompt while everything else is denied.
`owner` keeps the frictionless bypass.

## Deferred

Greeting on server-*join* needs the privileged **Server Members Intent**
toggled in the Discord Developer Portal (flipping `intents.members` in code
without it crashes the login). Until then the greeter greets on a visitor's
first message. No code depends on the intent yet.
