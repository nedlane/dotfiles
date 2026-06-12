#!/usr/bin/env bash
set -euo pipefail

# Verifies the worker completion push (hosts/wsl-desktop/bin/
# claude-worker-done-relay), a Claude Code Stop hook: when a thread-affine
# worker (started with --chat) ends a turn, it sends an HMAC-signed event to
# the local Hermes webhook route so the planner wakes up, reads the worker,
# and reports into the originating Discord thread. No model usage here.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELAY="$ROOT/hosts/wsl-desktop/bin/claude-worker-done-relay"

fail() {
  echo "claude-worker-done-relay smoke test failed: $*" >&2
  exit 1
}

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
stub="$base/stub-bin"
state="$base/state"
log="$base/curl.log"
cfg="$base/hermes-webhook"
mkdir -p "$stub" "$state/impl"

printf 'name=impl\nchat=discord:111:222\ndir=/home/u/projects/myproj\n' > "$state/impl/meta"
cat > "$cfg" <<'EOF'
HERMES_WEBHOOK_URL=http://127.0.0.1:8644/webhooks/claude-worker-events
HERMES_WEBHOOK_SECRET=testsecret123
EOF

cat > "$stub/curl" <<'STUB'
#!/usr/bin/env bash
args=()
data=""
while (($#)); do
  case "$1" in
    -d) data="$2"; args+=("$1" "$2"); shift 2 ;;
    *)  args+=("$1"); shift ;;
  esac
done
{ echo "curl ${args[*]}"; echo "DATA:$data"; } >> "$CURL_LOG"
STUB
chmod +x "$stub/curl"

hook_input='{"session_id":"abc-123","cwd":"/home/u/projects/myproj","stop_hook_active":false}'

run() { # run [env...] -- [stdin override]
  local envs=()
  while [[ "${1:-}" != "--" ]]; do envs+=("$1"); shift; done
  shift
  printf '%s' "${1:-$hook_input}" | env CURL_LOG="$log" PATH="$stub:/usr/bin:/bin" \
    CLAUDE_WORKERS_STATE="$state" CLAUDE_WORKERS_HERMES_WEBHOOK_FILE="$cfg" \
    "${envs[@]}" "$RELAY"
}

# --- a thread-affine worker's turn end posts a signed event ----------------------
out="$(run CLAUDE_WORKER=impl -- 2>&1)" || fail "relay exited non-zero: $out"
grep -q "DATA:" "$log" || fail "no event was posted"
grep -q '"event_type": "claude.worker.turn_ended"' "$log" || fail "missing event_type: $(cat "$log")"
grep -q '"worker": "impl"' "$log" || fail "missing worker: $(cat "$log")"
grep -q '"chat": "discord:111:222"' "$log" || fail "missing chat: $(cat "$log")"
grep -q "X-Webhook-Signature" "$log" || fail "missing signature header: $(cat "$log")"

# The signature must be the HMAC-SHA256 of the exact posted body.
body="$(grep '^DATA:' "$log" | head -1 | cut -d: -f2-)"
expected="$(printf '%s' "$body" | python3 -c '
import hashlib, hmac, sys
print(hmac.new(b"testsecret123", sys.stdin.buffer.read(), hashlib.sha256).hexdigest())')"
grep -q "X-Webhook-Signature: $expected" "$log" || fail "signature mismatch: $(cat "$log")"

# The secret must never leak to stdout/stderr.
grep -q "testsecret123" <<<"$out" && fail "secret leaked to output: $out"

# --- continuation stops (stop_hook_active) are ignored ----------------------------
: > "$log"
run CLAUDE_WORKER=impl -- '{"session_id":"abc","cwd":"/x","stop_hook_active":true}' \
  || fail "relay failed on continuation stop"
[[ -s "$log" ]] && fail "posted on stop_hook_active continuation"

# --- non-worker sessions and workers without --chat are ignored -------------------
: > "$log"
run -- || fail "relay failed on non-worker session"
[[ -s "$log" ]] && fail "non-worker session posted an event"
mkdir -p "$state/plain"
printf 'name=plain\ndir=/tmp\n' > "$state/plain/meta"
run CLAUDE_WORKER=plain -- || fail "relay failed on chatless worker"
[[ -s "$log" ]] && fail "worker without --chat posted an event"

# --- missing config file is a silent no-op -----------------------------------------
: > "$log"
rm "$cfg"
run CLAUDE_WORKER=impl -- || fail "relay failed without config file"
[[ -s "$log" ]] && fail "posted despite missing config"

echo "claude-worker-done-relay smoke tests passed"
