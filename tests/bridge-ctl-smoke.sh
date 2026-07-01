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

# --- start posts a signed start event ------------------------------------------------
: > "$log"
out="$(run start ghpr)" || fail "start failed: $out"
grep -q "claude.bridge.start" "$log" || fail "no start event: $(cat "$log")"
grep -q '"name": "ghpr"' "$log" || fail "name missing from start event: $(cat "$log")"
: > "$log"
run start >/dev/null 2>&1 && fail "start without a name accepted"
[[ -s "$log" ]] && fail "nameless start still hit the network"

# --- repos lists the local mapping --------------------------------------------------
out="$(run repos)" || fail "repos failed"
grep -q "ghpr" <<<"$out" || fail "repos missing mapping: $out"
grep -q "discord:111" <<<"$out" || fail "repos missing channel id: $out"

# --- addguest posts a signed guest-grant event ---------------------------------------
: > "$log"
out="$(run addguest ghpr 222222222222222222 collab)" || fail "addguest failed: $out"
grep -q "claude.bridge.addguest" "$log" || fail "no addguest event: $(cat "$log")"
grep -q '"name": "ghpr"' "$log" || fail "name missing from addguest: $(cat "$log")"
grep -q '"discord_id": "222222222222222222"' "$log" || fail "id missing from addguest: $(cat "$log")"
grep -q '"profile": "collab"' "$log" || fail "profile missing from addguest: $(cat "$log")"

# --- addguest defaults to the utility profile ----------------------------------------
: > "$log"
run addguest ghpr 222222222222222222 >/dev/null || fail "addguest default-profile failed"
grep -q '"profile": "utility"' "$log" || fail "addguest did not default to utility: $(cat "$log")"

# --- addguest rejects bad input before any network call ------------------------------
: > "$log"
run addguest ghpr not-a-number >/dev/null 2>&1 && fail "non-numeric discord_id accepted"
[[ -s "$log" ]] && fail "bad discord_id still hit the network"
: > "$log"
run addguest ghpr 123 bogusprofile >/dev/null 2>&1 && fail "bad profile accepted"
[[ -s "$log" ]] && fail "bad profile still hit the network"
: > "$log"
run addguest ghpr >/dev/null 2>&1 && fail "addguest without an id accepted"
[[ -s "$log" ]] && fail "incomplete addguest still hit the network"

# --- guests lists channels that have guest access ------------------------------------
gcfg="$base/config-guests.json"
cat > "$gcfg" <<'EOF'
{"repos": {"111": {"name": "ghpr", "dir": "/d", "guests": [42], "profile": "collab"},
           "222": {"name": "solo", "dir": "/e"}}}
EOF
out="$(env PATH="$stub:/usr/bin:/bin" \
  CLAUDE_WORKERS_BRIDGE_WEBHOOK_FILE="$base/bridge-webhook" \
  CLAUDE_BRIDGE_CONFIG="$gcfg" "$CTL" guests)" || fail "guests failed: $out"
grep -q "ghpr" <<<"$out" || fail "guests missing the guest channel: $out"
grep -q "collab" <<<"$out" || fail "guests missing the profile: $out"
grep -q "42" <<<"$out" || fail "guests missing the guest id: $out"
grep -q "solo" <<<"$out" && fail "guests listed a channel with no guests: $out"

# --- missing credentials fail cleanly ------------------------------------------------
env LOG="$log" PATH="$stub:/usr/bin:/bin" \
  CLAUDE_WORKERS_BRIDGE_WEBHOOK_FILE="$base/nope" \
  CLAUDE_BRIDGE_CONFIG="$base/config.json" "$CTL" addrepo x "$base/repo" \
  >/dev/null 2>&1 && fail "missing credentials did not fail"

echo "bridge-ctl smoke tests passed"
