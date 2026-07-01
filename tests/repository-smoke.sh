#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "repository smoke test failed: $*" >&2
  exit 1
}

while IFS= read -r script; do
  [[ -x "$script" ]] || fail "$script is not executable"
# The control-plane tools live in the agent-bridge submodule; include them only
# when it's checked out (it may not be in CI while the repo is private — its own
# CI checks their executability there).
exec_dirs=(scripts tests shared/bin hosts/mac/bin)
[ -d hosts/wsl-desktop/agent-bridge/bin ] && exec_dirs+=(hosts/wsl-desktop/agent-bridge/bin)
done < <(find "${exec_dirs[@]}" \
  -name __pycache__ -prune -o \
  -type f \( -name '*.sh' -o -path 'shared/bin/*' -o -path 'hosts/mac/bin/*' -o -path 'hosts/wsl-desktop/agent-bridge/bin/*' \) -print | sort)

if git ls-files | grep -Eq '(^|/)(\.ssh|\.config|\.gitconfig|\.zshrc)(/|$)'; then
  fail "tracked home-directory state found"
fi

for host in mac wsl-desktop minipc minipc2 pi; do
  [[ -f "hosts/$host/host.zsh" ]] || fail "missing hosts/$host/host.zsh"
  [[ -f "hosts/$host/host.tmux" ]] || fail "missing hosts/$host/host.tmux"
done

git diff --check
echo "repository smoke tests passed"
