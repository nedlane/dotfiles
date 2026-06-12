#!/usr/bin/env bash
set -euo pipefail

# Verifies discord-notify (hosts/wsl-desktop/bin/discord-notify): it prefers
# the Hermes bot (`hermes send`), falls back to the webhook file, tags worker
# sessions, reads stdin with '-', and never leaks the webhook URL.

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
mkdir -p "$stub"
printf 'https://discord.example/api/webhooks/123/SECRETTOKEN\n' > "$webhook_file"

cat > "$stub/hermes" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "send" ]]; then shift; fi
body=""
case " $* " in *" -f - "*) body="$(cat)" ;; esac
echo "hermes-send $* :: $body" >> "$LOG"
exit "${HERMES_STUB_EXIT:-0}"
STUB
cat > "$stub/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$LOG"
STUB
chmod +x "$stub/hermes" "$stub/curl"

run() { # run [env...] -- [args...]
  local envs=()
  while [[ "${1:-}" != "--" ]]; do envs+=("$1"); shift; done
  shift
  env "${envs[@]}" LOG="$log" PATH="$stub:$PATH" \
    CLAUDE_WORKERS_DISCORD_WEBHOOK_FILE="$webhook_file" "$NOTIFY" "$@"
}

# --- default: routes through the Hermes bot to the discord home channel --------
: > "$log"
run -- "build finished" || fail "plain send failed"
grep -q "hermes-send .*discord" "$log" || fail "did not target discord: $(cat "$log")"
grep -q "build finished" "$log" || fail "message text missing: $(cat "$log")"

# --- worker sessions are tagged so you can tell who is talking ------------------
: > "$log"
run CLAUDE_WORKER=impl -- "tests are green" || fail "worker send failed"
grep -q "worker:impl" "$log" || fail "worker tag missing: $(cat "$log")"

# --- a worker with a recorded chat defaults to its own thread --------------------
mkdir -p "$base/state/impl"
printf 'name=impl\nchat=discord:111:222\n' > "$base/state/impl/meta"
: > "$log"
run CLAUDE_WORKER=impl CLAUDE_WORKERS_STATE="$base/state" -- "threaded ping" \
  || fail "thread-default send failed"
grep -q -- "-t discord:111:222" "$log" || fail "worker chat default not used: $(cat "$log")"

# --- explicit target passes through ----------------------------------------------
: > "$log"
run -- -t discord:#ops "deploy done" || fail "explicit target failed"
grep -q -- "-t discord:#ops" "$log" || fail "target not passed through: $(cat "$log")"

# --- '-' reads stdin --------------------------------------------------------------
: > "$log"
printf 'line1\nline2\n' | run -- - || fail "stdin send failed"
grep -q "hermes-send" "$log" || fail "stdin send did not call hermes: $(cat "$log")"

# --- no hermes: falls back to the webhook, without leaking the URL ----------------
# PATH is pinned to the stub dir + system dirs so a real hermes install on the
# test machine can't be picked up (and message a real channel).
: > "$log"
rm "$stub/hermes"
run_no_hermes() {
  env LOG="$log" PATH="$stub:/usr/bin:/bin" \
    CLAUDE_WORKERS_DISCORD_WEBHOOK_FILE="$webhook_file" "$NOTIFY" "$@"
}
out="$(run_no_hermes "fallback message" 2>&1)" || fail "webhook fallback failed: $out"
grep -q "curl " "$log" || fail "webhook fallback did not curl: $(cat "$log")"
grep -q "fallback message" "$log" || fail "fallback message missing: $(cat "$log")"
grep -q "SECRETTOKEN" <<<"$out" && fail "webhook URL leaked to output: $out"

# --- no transport at all: clear error, non-zero exit -------------------------------
rm "$webhook_file"
run_no_hermes "nowhere to go" >/dev/null 2>&1 && fail "send with no transport unexpectedly succeeded"

echo "discord-notify smoke tests passed"
