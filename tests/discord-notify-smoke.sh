#!/usr/bin/env bash
set -euo pipefail

# Verifies discord-notify (hosts/wsl-desktop/bin/discord-notify): chat-bound
# workers and explicit discord:<id> targets route through the claude-bridge
# (signed localhost event), everything else falls back to the webhook, worker
# sessions are tagged, '-' reads stdin, and no secret ever leaks.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTIFY="$ROOT/hosts/wsl-desktop/bin/discord-notify"

fail() {
  echo "discord-notify smoke test failed: $*" >&2
  exit 1
}

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
stub="$base/stub-bin"
log="$base/calls.log"
webhook_file="$base/discord-webhook"
bridge_cfg="$base/bridge-webhook"
state="$base/state"
mkdir -p "$stub" "$state/impl"

printf 'https://discord.example/api/webhooks/123/SECRETTOKEN\n' > "$webhook_file"
cat > "$bridge_cfg" <<'EOF'
BRIDGE_WEBHOOK_URL=http://127.0.0.1:8765/event
BRIDGE_WEBHOOK_SECRET=bridgesecret
EOF
printf 'name=impl\nchat=discord:111:222\n' > "$state/impl/meta"

cat > "$stub/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$LOG"
STUB
chmod +x "$stub/curl"

run() { # run [env...] -- [args...]
  local envs=()
  while [[ "${1:-}" != "--" ]]; do envs+=("$1"); shift; done
  shift
  env LOG="$log" PATH="$stub:/usr/bin:/bin" \
    CLAUDE_WORKERS_DISCORD_WEBHOOK_FILE="$webhook_file" \
    CLAUDE_WORKERS_BRIDGE_WEBHOOK_FILE="$bridge_cfg" \
    CLAUDE_WORKERS_STATE="$state" "${envs[@]}" "$NOTIFY" "$@"
}

# --- no worker context: falls back to the webhook (main channel) ----------------
: > "$log"
out="$(run -- "build finished" 2>&1)" || fail "plain send failed: $out"
grep -q "discord.example" "$log" || fail "did not hit the webhook: $(cat "$log")"
grep -q "build finished" "$log" || fail "message text missing: $(cat "$log")"
grep -q "SECRETTOKEN" <<<"$out" && fail "webhook URL leaked to output: $out"

# --- a chat-bound worker routes through the bridge into its channel --------------
: > "$log"
run CLAUDE_WORKER=impl -- "tests are green" || fail "worker send failed"
grep -q "claude.worker.send" "$log" || fail "no bridge event: $(cat "$log")"
grep -q "discord:111:222" "$log" || fail "worker chat not targeted: $(cat "$log")"
grep -q "worker:impl" "$log" || fail "worker tag missing: $(cat "$log")"
grep -q '"worker": "impl"' "$log" || fail "event missing worker field (bridge can't suppress its fallback): $(cat "$log")"
grep -q "X-Webhook-Signature" "$log" || fail "bridge event not signed: $(cat "$log")"
grep -q "discord.example" "$log" && fail "chat-bound send fell back to the webhook"

# --- explicit discord:<id> target also goes via the bridge ------------------------
: > "$log"
run -- -t discord:999 "deploy done" || fail "explicit target failed"
grep -q '\\"chat\\": \\"discord:999\\"\|"chat": "discord:999"' "$log" || fail "explicit target not used: $(cat "$log")"

# --- a worker without recorded chat is tagged but uses the webhook ----------------
mkdir -p "$state/plain"
printf 'name=plain\n' > "$state/plain/meta"
: > "$log"
run CLAUDE_WORKER=plain -- "no chat here" || fail "chatless worker send failed"
grep -q "discord.example" "$log" || fail "chatless worker did not use webhook: $(cat "$log")"
grep -q "worker:plain" "$log" || fail "chatless worker tag missing: $(cat "$log")"

# --- '-' reads stdin ----------------------------------------------------------------
: > "$log"
printf 'line1\nline2\n' | run -- - || fail "stdin send failed"
grep -q "line1" "$log" || fail "stdin body missing: $(cat "$log")"

# --- --help prints usage and sends NOTHING (agents spam Discord otherwise) ----------
: > "$log"
out="$(run -- --help 2>&1)" || fail "--help should exit 0: $out"
grep -q "Usage:" <<<"$out" || fail "--help did not print usage: $out"
grep -q "\-i, --image" <<<"$out" || fail "--help did not document attachments: $out"
[[ -s "$log" ]] && fail "--help sent something to Discord: $(cat "$log")"

# --- attachments: a chat-bound worker rides the file path in the bridge event -------
img="$base/chart.png"
printf 'PNGDATA' > "$img"
: > "$log"
run CLAUDE_WORKER=impl -- -i "$img" "coverage chart" || fail "worker image send failed"
grep -q "claude.worker.send" "$log" || fail "image: no bridge event: $(cat "$log")"
grep -q '"attachments"' "$log" || fail "image: event missing attachments: $(cat "$log")"
grep -q "$img" "$log" || fail "image: attachment path not in event: $(cat "$log")"
grep -q "discord.example" "$log" && fail "image: chat-bound send fell back to webhook"

# --- attachments via the webhook fallback go up as a multipart upload ---------------
: > "$log"
run -- -i "$img" "no worker, main channel" || fail "webhook image send failed"
grep -q "files\[0\]=@$img" "$log" || fail "image: not uploaded as multipart: $(cat "$log")"
grep -q "payload_json=" "$log" || fail "image: caption payload missing: $(cat "$log")"

# --- an attachment with no message is allowed -----------------------------------------
: > "$log"
run -- -i "$img" || fail "image-only send (no message) failed"
grep -q "files\[0\]=@$img" "$log" || fail "image-only: not uploaded: $(cat "$log")"

# --- a missing attachment is a clear error, and nothing is sent -----------------------
: > "$log"
run -- -i "$base/nope.png" "ghost" >/dev/null 2>&1 && fail "missing attachment unexpectedly succeeded"
[[ -s "$log" ]] && fail "missing attachment still posted: $(cat "$log")"

# --- no transport at all: clear error, non-zero exit ---------------------------------
rm "$webhook_file" "$bridge_cfg"
run -- "nowhere to go" >/dev/null 2>&1 && fail "send with no transport unexpectedly succeeded"

echo "discord-notify smoke tests passed"
