#!/usr/bin/env bash
set -euo pipefail

# Verifies the Discord todo relay (hosts/wsl-desktop/bin/claude-worker-todo-relay),
# a Claude Code PostToolUse hook for TodoWrite: it formats a worker's live task
# checklist and posts it to a Discord webhook with no model/token usage.
# Checks: posting, worker-only filtering, dedupe, graceful no-webhook exit,
# and that the webhook URL never leaks to stdout/stderr.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELAY="$ROOT/hosts/wsl-desktop/bin/claude-worker-todo-relay"

fail() {
  echo "claude-worker-todo-relay smoke test failed: $*" >&2
  exit 1
}

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
stub="$base/stub-bin"
state="$base/state"
curl_log="$base/curl.log"
webhook_file="$base/discord-webhook"
mkdir -p "$stub" "$state"

printf 'https://discord.example/api/webhooks/123/SECRETTOKEN\n' > "$webhook_file"

# Stub curl: records argv and the posted payload.
cat > "$stub/curl" <<'STUB'
#!/usr/bin/env bash
{ echo "curl $*"; } >> "$CURL_LOG"
STUB
chmod +x "$stub/curl"

hook_input='{
  "session_id": "abc-123",
  "cwd": "/home/u/projects/myproj",
  "tool_name": "TodoWrite",
  "tool_input": {"todos": [
    {"content": "Write the failing test", "status": "completed", "activeForm": "Writing the failing test"},
    {"content": "Implement the fix", "status": "in_progress", "activeForm": "Implementing the fix"},
    {"content": "Run the suite", "status": "pending", "activeForm": "Running the suite"}
  ]}
}'

# run [extra env...] -> feeds the sample hook input to the relay.
run() {
  printf '%s' "$hook_input" | env CURL_LOG="$curl_log" PATH="$stub:$PATH" \
    CLAUDE_WORKERS_STATE="$state" \
    CLAUDE_WORKERS_DISCORD_WEBHOOK_FILE="$webhook_file" \
    "$@" "$RELAY"
}

# --- a worker session posts its checklist -------------------------------------
out="$(run CLAUDE_WORKER=impl 2>&1)" || fail "relay exited non-zero: $out"
[[ -f "$curl_log" ]] || fail "no webhook post was made"
grep -q "worker:impl" "$curl_log" || fail "post missing worker name: $(cat "$curl_log")"
grep -q "myproj" "$curl_log" || fail "post missing project dir: $(cat "$curl_log")"
grep -q "Implementing the fix" "$curl_log" || fail "post missing in-progress task: $(cat "$curl_log")"
grep -q "Run the suite" "$curl_log" || fail "post missing pending task: $(cat "$curl_log")"

# The webhook URL (a secret) must never appear on stdout/stderr.
grep -q "SECRETTOKEN" <<<"$out" && fail "webhook URL leaked to output: $out"

# --- identical state is deduped, changed state posts again ----------------------
: > "$curl_log"
run CLAUDE_WORKER=impl >/dev/null 2>&1
[[ -s "$curl_log" ]] && fail "duplicate todo state was re-posted"
hook_input="${hook_input/Run the suite/Run the full suite}"
run CLAUDE_WORKER=impl >/dev/null 2>&1
[[ -s "$curl_log" ]] || fail "changed todo state was not posted"

# --- manual (non-worker) sessions are ignored -----------------------------------
: > "$curl_log"
run >/dev/null 2>&1 || fail "relay failed on a non-worker session"
[[ -s "$curl_log" ]] && fail "non-worker session posted to Discord"

# --- TaskCreate/TaskUpdate render the on-disk task list -------------------------
tasks_dir="$base/tasks"
mkdir -p "$tasks_dir"
printf '{"id":"1","subject":"Build the parser","status":"completed"}\n' > "$tasks_dir/1.json"
printf '{"id":"2","subject":"Wire the relay","status":"in_progress"}\n' > "$tasks_dir/2.json"
printf '{"id":"3","subject":"Old idea","status":"deleted"}\n' > "$tasks_dir/3.json"
task_hook='{"session_id":"abc-123","cwd":"/home/u/projects/myproj","tool_name":"TaskUpdate","tool_input":{"taskId":"2","status":"in_progress"}}'
: > "$curl_log"
printf '%s' "$task_hook" | env CURL_LOG="$curl_log" PATH="$stub:$PATH" \
  CLAUDE_WORKERS_STATE="$state" CLAUDE_TASKS_DIR="$tasks_dir" \
  CLAUDE_WORKERS_DISCORD_WEBHOOK_FILE="$webhook_file" CLAUDE_WORKER=impl \
  "$RELAY" || fail "relay failed on TaskUpdate hook"
grep -q "Build the parser" "$curl_log" || fail "task list post missing completed task: $(cat "$curl_log")"
grep -q "Wire the relay" "$curl_log" || fail "task list post missing in-progress task: $(cat "$curl_log")"
grep -q "Old idea" "$curl_log" && fail "deleted task was posted: $(cat "$curl_log")"

# --- a worker with a recorded chat posts into its channel via the bridge --------
mkdir -p "$state/threaded"
printf 'name=threaded\nchat=discord:111:222\n' > "$state/threaded/meta"
bridge_cfg="$base/bridge-webhook"
cat > "$bridge_cfg" <<'EOF'
BRIDGE_WEBHOOK_URL=http://127.0.0.1:8765/event
BRIDGE_WEBHOOK_SECRET=bridgesecret
EOF
: > "$curl_log"
(
  export CURL_LOG="$curl_log" PATH="$stub:$PATH" CLAUDE_WORKERS_STATE="$state" \
    CLAUDE_WORKERS_BRIDGE_WEBHOOK_FILE="$bridge_cfg" \
    CLAUDE_WORKERS_DISCORD_WEBHOOK_FILE="$webhook_file" CLAUDE_WORKER=threaded
  printf '%s' "$hook_input" | "$RELAY" >/dev/null 2>&1
) || fail "chat-bound relay failed"
grep -q "claude.worker.send" "$curl_log" || fail "no bridge send event: $(cat "$curl_log")"
grep -q "discord:111:222" "$curl_log" || fail "did not target the worker's channel: $(cat "$curl_log")"
grep -q "Implementing the fix" "$curl_log" || fail "channel post missing checklist: $(cat "$curl_log")"
grep -q "X-Webhook-Signature" "$curl_log" || fail "bridge event not signed: $(cat "$curl_log")"
grep -q "discord.example" "$curl_log" && fail "chat-bound worker fell back to the webhook"

# --- a missing webhook file is a silent no-op, never an error -------------------
: > "$curl_log"
rm "$webhook_file"
run CLAUDE_WORKER=impl >/dev/null 2>&1 || fail "relay failed without a webhook file"
[[ -s "$curl_log" ]] && fail "posted despite missing webhook file"
printf 'https://discord.example/api/webhooks/123/SECRETTOKEN\n' > "$webhook_file"

echo "claude-worker-todo-relay smoke tests passed"
