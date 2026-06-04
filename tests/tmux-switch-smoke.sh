#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "tmux switch smoke test failed: $*" >&2
  exit 1
}

run_case() {
  local choice=$1 sessions=$2 log
  log="$(mktemp)"

  SWITCH_LOG="$log" SWITCH_CHOICE="$choice" SWITCH_SESSIONS="$sessions" ROOT="$ROOT" zsh -c '
    tmux() {
      print -r -- "tmux $*" >> "$SWITCH_LOG"
      if [[ "$1" == has-session ]]; then return 1; fi
      if [[ "$1 $2 $3" == "list-sessions -F #S" ]]; then print main; fi
      if [[ "$1 $2 $3" == "list-sessions -F #{session_attached}|#{session_name}" ]]; then
        print -r -- "$SWITCH_SESSIONS"
      fi
    }
    fzf() { cat >/dev/null; print -r -- "$SWITCH_CHOICE"; }
    tailscale() { return 0; }
    timeout() { return 0; }
    source "$ROOT/shared/bin/tmux-switch"
  '

  printf '%s\n' "$log"
}

log="$(run_case 'local: main' $'0|desktop/work\n1|main')"
switch_line="$(grep -n 'tmux switch-client -t main' "$log" | cut -d: -f1)"
list_line="$(grep -nF 'tmux list-sessions -F #{session_attached}|#{session_name}' "$log" | cut -d: -f1)"
kill_line="$(grep -n 'tmux kill-session -t desktop/work' "$log" | cut -d: -f1)"
[[ "$switch_line" -lt "$list_line" && "$list_line" -lt "$kill_line" ]] \
  || fail "local switch did not prune after switching"
rm -f "$log"

log="$(run_case 'desktop: work' $'0|pi/main\n1|desktop/work')"
switch_line="$(grep -n 'tmux switch-client -t desktop/work' "$log" | cut -d: -f1)"
list_line="$(grep -nF 'tmux list-sessions -F #{session_attached}|#{session_name}' "$log" | cut -d: -f1)"
kill_line="$(grep -n 'tmux kill-session -t pi/main' "$log" | cut -d: -f1)"
[[ "$switch_line" -lt "$list_line" && "$list_line" -lt "$kill_line" ]] \
  || fail "remote switch did not prune after switching"
if grep -q 'tmux kill-session -t desktop/work' "$log"; then
  fail "selected remote proxy was pruned"
fi
rm -f "$log"

echo "tmux switch smoke tests passed"
