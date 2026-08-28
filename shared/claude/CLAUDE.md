# Global Claude Instructions (Ned Lane)

## Git commits

- Commit signing is configured globally via SSH using
  `~/.ssh/id_ed25519_signing` (passphrase-free, `gpg.format=ssh`,
  `commit.gpgsign=true`).
  Run plain `git commit` — do not pass `-c commit.gpgsign=false`,
  `--no-gpg-sign`, `-S`, or any other signing override.
  Signing is automatic; flags only get in the way.
- If signing fails, stop and report the error — do not bypass it.

## Branch names

- Before every push, check the branch name with `git branch --show-current`.
- Never push a branch whose name starts with an AI tool, provider, model, or
  agent-harness namespace. Forbidden prefixes include, but are not limited to,
  `ai/`, `agent/`, `claude/`, `codex/`, `copilot/`, `cursor/`, `gemini/`,
  `opencode/`, `t3code/`, and `windsurf/`.
- Rename such a branch to a neutral, project-appropriate name before pushing or
  opening a pull request. Never create or update a remote branch under an AI
  tool namespace unless I explicitly instruct you to do so.

## AI attribution

- Never add `Co-Authored-By:
  Claude ...` or any AI attribution trailers.
- Never mention Claude, Claude Code, Anthropic, or any AI tool in commit
  messages, PR titles, or PR bodies.
- This applies to every repo unless a project's CLAUDE.md explicitly says
  otherwise.

## Reviewing pull requests

- When I ask you to review a PR (or "review all PRs"), don't stop at a chat-only
  writeup — post it to GitHub with `gh pr review` and conclude with a decisive
  verdict:
  `--approve` if nothing blocks, `--request-changes` if there are blocking
  issues.
  Avoid the neutral `--comment` unless the call is genuinely ambiguous.
- For "all PRs", run `gh pr list` and handle each one:
  review → post → verdict.
- I shouldn't have to ask for the posting or the verdict — that's the default.

## GitHub operations — default tool

- Use the **`gh` CLI for all GitHub work** by default:
  PR reviews, issues, comments, repo/branch operations, API calls, etc. This
  includes posting PR reviews (`gh pr review --approve` / `--request-changes`).

## Subagents

- Do not use subagents just to appear thorough.
  Use them when they have a clear job that can be done independently.
- The main agent remains responsible for the final answer, final code changes,
  final GitHub actions, and verifying important subagent findings.
