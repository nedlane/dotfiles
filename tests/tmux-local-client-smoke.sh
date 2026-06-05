#!/usr/bin/env bash
# Verifies the `prefix w` nesting guard: tmux-local-client must treat a client
# whose environment carries SSH_CONNECTION as remote (exit 1 -> switcher
# disabled) and everything else as local (exit 0 -> switcher enabled). This is
# what stops a session reached over SSH from re-launching the switcher and
# nesting tmux through tmux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/shared/bin/tmux-local-client"

fail() {
  echo "tmux-local-client smoke test failed: $*" >&2
  exit 1
}

# A process WITHOUT SSH_CONNECTION is local -> guard exits 0.
env -u SSH_CONNECTION sleep 30 &
local_pid=$!
"$GUARD" "$local_pid" || fail "client without SSH_CONNECTION was treated as remote"
kill "$local_pid" 2>/dev/null || true

# A process WITH SSH_CONNECTION (as `tailscale ssh` sets) is remote -> exits 1.
env SSH_CONNECTION="10.0.0.1 12345 10.0.0.2 22" sleep 30 &
remote_pid=$!
if "$GUARD" "$remote_pid"; then
  fail "client with SSH_CONNECTION was treated as local"
fi
kill "$remote_pid" 2>/dev/null || true

# Unknown/empty PID fails OPEN (local) so the switcher never breaks on a fluke.
"$GUARD" "" || fail "empty pid should fail open to local"

echo "tmux-local-client smoke tests passed"
