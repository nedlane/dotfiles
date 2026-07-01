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
done < <(find scripts tests shared/bin hosts/mac/bin hosts/wsl-desktop/agent-bridge/bin \
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
