## ghpr — only on explicit request

- `ghpr` is my private PR-review tool (repo `nedlane/ghpr`, local checkout at
  `~/projects/ghpr`). It approves / requests-changes / comments on PRs using a
  PAT stored in that repo's git-ignored `.env`.
- **Only use `ghpr` when I explicitly name it.** Otherwise default to `gh`
  above — do not reach for `ghpr` on your own.
- When I do ask for it, run it from the repo root. Single-call form:
  ```bash
  ./ghpr.sh --json exec --json '{"action":"approve","repo":"owner/name","pr":123,"body":"LGTM"}'
  ```
  Actions: `approve`, `request_changes`, `comment`, `issue_comment`, `get`,
  `list`. Add `--dry-run` to validate without calling GitHub. Exit codes:
  `0` ok · `2` bad input · `3` no token · `4` API error. Run `./ghpr.sh schema`
  for the full input contract; see the repo's `AGENTS.md` for details.
