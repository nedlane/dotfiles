# Contributing

These are my personal dotfiles, published so others can read, fork, and borrow
from them. They're tailored to my machines and workflow, so I'm generally **not
looking for feature PRs**.

That said:

- **Spot a bug or a security issue?** Please open an issue — that's genuinely
  useful and appreciated.
- **Want to use these?** Fork away. No need to ask.
- **Small, obviously-correct fixes** (typos, broken links, portability nits) are
  welcome as PRs; larger changes are unlikely to be merged since they'd pull the
  config away from how I actually use it.

CI runs ShellCheck, `bash -n`/`zsh -n`, `luac`/StyLua for the Neovim config, a
gitleaks secret scan, and a set of smoke tests under `tests/`. Run
`./tests/repository-smoke.sh` and the relevant `tests/*-smoke.sh` before
proposing a change.
