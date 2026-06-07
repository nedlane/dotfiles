# Global Claude Instructions (Ned Lane)

## Git commits

- Commit signing is configured globally via SSH using
  `~/.ssh/id_ed25519_signing` (passphrase-free, `gpg.format=ssh`,
  `commit.gpgsign=true`). Run plain `git commit` — do not pass
  `-c commit.gpgsign=false`, `--no-gpg-sign`, `-S`, or any other signing
  override. Signing is automatic; flags only get in the way.
- If signing fails, stop and report the error — do not bypass it.

## AI attribution

- Never add `Co-Authored-By: Claude ...` or any AI/Anthropic attribution
  trailer to commit messages.
- Never mention Claude, Claude Code, Anthropic, or any AI tool in commit
  messages, PR titles, or PR bodies.
- This applies to every repo unless a project's CLAUDE.md explicitly says
  otherwise.

## Reviewing pull requests

- When I ask you to review a PR (or "review all PRs"), don't stop at a
  chat-only writeup — post it to GitHub with `gh pr review` and conclude with
  a decisive verdict: `--approve` if nothing blocks, `--request-changes` if
  there are blocking issues. Avoid the neutral `--comment` unless the call is
  genuinely ambiguous.
- For "all PRs", run `gh pr list` and handle each one: review → post → verdict.
- I shouldn't have to ask for the posting or the verdict — that's the default.

## GitHub operations — default tool

- Use the **`gh` CLI for all GitHub work** by default: PR reviews, issues,
  comments, repo/branch operations, API calls, etc. This includes posting PR
  reviews (`gh pr review --approve` / `--request-changes`).
