#!/usr/bin/env bash
set -euo pipefail

# Verifies bridge-ctl (hosts/wsl-desktop/bin/bridge-ctl), the tools-based
# bridge interface for workers: addrepo posts a signed channel-creation
# event, bad input fails before any network call, and repos lists the local
# mapping. Nothing real is contacted.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$ROOT/hosts/wsl-desktop/bin/bridge-ctl"

fail() {
  echo "bridge-ctl smoke test failed: $*" >&2
  exit 1
}

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
stub="$base/stub-bin"
log="$base/curl.log"
mkdir -p "$stub" "$base/repo"

cat > "$base/bridge-webhook" <<'EOF'
BRIDGE_WEBHOOK_URL=http://127.0.0.1:8765/event
BRIDGE_WEBHOOK_SECRET=ctlsecret
EOF
cat > "$base/config.json" <<'EOF'
{"repos": {"111": {"name": "ghpr", "dir": "/home/u/projects/ghpr"}}}
EOF

cat > "$stub/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$LOG"
echo '{"status": "ok", "channel_id": "222"}'
STUB
chmod +x "$stub/curl"

run() {
  env LOG="$log" PATH="$stub:/usr/bin:/bin" \
    CLAUDE_WORKERS_BRIDGE_WEBHOOK_FILE="$base/bridge-webhook" \
    CLAUDE_BRIDGE_CONFIG="$base/config.json" "$CTL" "$@"
}

# --- addrepo posts a signed creation event and surfaces the response -------------
out="$(run addrepo myrepo "$base/repo")" || fail "addrepo failed: $out"
grep -q "claude.bridge.addrepo" "$log" || fail "no addrepo event: $(cat "$log")"
grep -q '"name": "myrepo"' "$log" || fail "name missing from event: $(cat "$log")"
grep -q "$base/repo" "$log" || fail "path missing from event: $(cat "$log")"
grep -q "X-Webhook-Signature" "$log" || fail "event not signed: $(cat "$log")"
grep -q '"channel_id": "222"' <<<"$out" || fail "bridge response not surfaced: $out"

# --- a missing directory fails before any network call ----------------------------
: > "$log"
run addrepo bad /definitely/not/a/dir >/dev/null 2>&1 && fail "bad dir accepted"
[[ -s "$log" ]] && fail "bad dir still hit the network"

# --- repos lists the local mapping --------------------------------------------------
out="$(run repos)" || fail "repos failed"
grep -q "ghpr" <<<"$out" || fail "repos missing mapping: $out"
grep -q "discord:111" <<<"$out" || fail "repos missing channel id: $out"

# --- missing credentials fail cleanly ------------------------------------------------
env LOG="$log" PATH="$stub:/usr/bin:/bin" \
  CLAUDE_WORKERS_BRIDGE_WEBHOOK_FILE="$base/nope" \
  CLAUDE_BRIDGE_CONFIG="$base/config.json" "$CTL" addrepo x "$base/repo" \
  >/dev/null 2>&1 && fail "missing credentials did not fail"

echo "bridge-ctl smoke tests passed"
