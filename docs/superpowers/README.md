# Design notes (historical)

These are **dated, internal design artifacts** kept for provenance — brainstorming
specs and implementation plans captured while building things out. They describe
the state of thinking *at their date* and are **not** current documentation.

- They predate later changes: some name subsystems that were removed or renamed
  (e.g. an early "Hermes"/"OpenClaw"/"Codex" planner era that no longer exists —
  there is **no LLM in the routing path** today), and reference paths that have
  since moved (the Discord control plane was extracted into the private
  `agent-bridge` submodule under `hosts/wsl-desktop/agent-bridge/`).
- For how the control plane actually works now, see
  [`../agent-control-plane.md`](../agent-control-plane.md).

Treat anything here as a snapshot, not a spec to build against.
