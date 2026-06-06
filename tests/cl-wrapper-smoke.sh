#!/usr/bin/env bash
set -euo pipefail

# Verifies the `cl` Claude Code launcher (shared/zsh/aliases.zsh): it forces a
# remote-control session whose title is "<host> / <dir>" so each device is
# identifiable, passes extra args through, and yields to an explicit --name.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "cl wrapper smoke test failed: $*" >&2
  exit 1
}

# run <host> <projname> [cl args...] -> prints the args `cl` passed to claude.
run() {
  local host="$1" proj="$2"
  shift 2
  local base dir log
  base="$(mktemp -d)"
  dir="$base/$proj"
  mkdir -p "$dir"
  log="$base/log"

  # Stub `claude` as a function so the wrapper records its argv without
  # launching anything; run from $dir so ${PWD:t} resolves to <projname>.
  CL_LOG="$log" CL_DIR="$dir" DOTFILES_HOST="$host" ROOT="$ROOT" zsh -c '
    claude() { print -r -- "claude $*" >> "$CL_LOG"; }
    cd "$CL_DIR"
    source "$ROOT/shared/zsh/aliases.zsh"
    cl "$@"
  ' cl-smoke "$@"

  cat "$log"
  rm -rf "$base"
}

# Default launch: always-on remote control with a "<host> / <dir>" title.
out="$(run wsl-desktop dotfiles)"
grep -qF -- '--dangerously-skip-permissions' <<<"$out" || fail "missing --dangerously-skip-permissions: $out"
grep -qF -- '--remote-control' <<<"$out" || fail "missing --remote-control: $out"
grep -qF -- '--name wsl-desktop / dotfiles' <<<"$out" || fail "missing device/folder title: $out"

# Extra args pass through and the title reflects host + directory.
out="$(run minipc myproj --model opus)"
grep -qF -- '--name minipc / myproj' <<<"$out" || fail "title wrong with passthrough: $out"
grep -qF -- '--model opus' <<<"$out" || fail "passthrough arg dropped: $out"

# An explicit --name from the caller wins; no injected title.
out="$(run wsl-desktop dotfiles --name custom)"
grep -qF -- '--name custom' <<<"$out" || fail "explicit --name dropped: $out"
if grep -qF -- 'wsl-desktop /' <<<"$out"; then
  fail "injected title despite explicit --name: $out"
fi

# An explicit -n short flag wins too.
out="$(run pi scripts -n short)"
grep -qF -- '-n short' <<<"$out" || fail "explicit -n dropped: $out"
if grep -qF -- 'pi /' <<<"$out"; then
  fail "injected title despite explicit -n: $out"
fi

echo "cl wrapper smoke tests passed"
