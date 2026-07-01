#!/usr/bin/env bash
set -euo pipefail

# Verifies the control-plane readiness check (hosts/wsl-desktop/agent-bridge/bin/
# agent-checkup) against a fully stubbed environment: Claude subscription
# detection, bridge runtime/credential checks, forbidden-env warnings,
# missing-tool failures, and that no secret values are echoed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKUP="$ROOT/hosts/wsl-desktop/agent-bridge/bin/agent-checkup"

fail() {
  echo "agent-checkup smoke test failed: $*" >&2
  exit 1
}

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
home="$base/home"
stub="$base/stub-bin"
mkdir -p "$home/.claude" "$home/.config/claude-workers" "$home/.config/claude-bridge" "$stub"

for tool in claude tmux; do
  printf '#!/usr/bin/env bash\necho "%s 1.0.0"\n' "$tool" > "$stub/$tool"
done
# Stub python3 (so `import discord` "succeeds") and systemctl (service active).
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/python3"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/systemctl"
chmod +x "$stub"/*

printf '{"claudeAiOauth": {"accessToken": "fake-claude-secret"}}\n' > "$home/.claude/.credentials.json"
printf 'NOT-A-REAL-TOKEN-VALUE\n' > "$home/.config/claude-workers/discord-bot-token"
printf 'https://discord.example/api/webhooks/1/x\n' > "$home/.config/claude-workers/discord-webhook"
printf 'BRIDGE_WEBHOOK_URL=http://127.0.0.1:8765/event\nBRIDGE_WEBHOOK_SECRET=fake-bridge-secret\n' \
  > "$home/.config/claude-workers/bridge-webhook"
printf '{"repos": {}}\n' > "$home/.config/claude-bridge/config.json"

# run [env overrides...] -> runs agent-checkup in the stub environment.
run() {
  env -i HOME="$home" PATH="$stub:$ROOT/shared/bin:$ROOT/hosts/wsl-desktop/agent-bridge/bin:/usr/bin:/bin" \
    "$@" "$CHECKUP" 2>&1
}

# --- healthy setup: exit 0, subscription + bridge pieces detected ----------------
out="$(run)" || fail "healthy environment reported failure: $out"
grep -q "PASS.*tmux" <<<"$out" || fail "missing tmux pass: $out"
grep -qi "PASS.*claude.*interactive\|PASS.*interactive.*claude" <<<"$out" || fail "claude interactive auth not detected: $out"
grep -qi "PASS.*discord.py" <<<"$out" || fail "discord.py check missing: $out"
grep -qi "PASS.*bot token" <<<"$out" || fail "bot token check missing: $out"
grep -qi "PASS.*bridge config" <<<"$out" || fail "bridge config check missing: $out"
grep -qi "PASS.*claude-bridge service" <<<"$out" || fail "bridge service check missing: $out"
grep -qi "manual" <<<"$out" || fail "no manual checks section: $out"

# Secret values from credential files must never be echoed.
grep -q "fake-claude-secret\|NOT-A-REAL-TOKEN-VALUE\|fake-bridge-secret" <<<"$out" \
  && fail "secret value leaked: $out"

# --- forbidden env vars are flagged ------------------------------------------------
out="$(run ANTHROPIC_API_KEY=x)" || true
grep -qi "WARN.*ANTHROPIC_API_KEY" <<<"$out" || fail "ANTHROPIC_API_KEY not flagged: $out"

# --- a missing bot token is a FAIL --------------------------------------------------
mv "$home/.config/claude-workers/discord-bot-token" "$base/token.bak"
if out="$(run)"; then
  fail "missing bot token did not fail the checkup: $out"
fi
grep -qi "FAIL.*token" <<<"$out" || fail "missing token not reported: $out"
mv "$base/token.bak" "$home/.config/claude-workers/discord-bot-token"

# --- a missing tool is a FAIL with non-zero exit -------------------------------------
rm "$stub/claude"
if out="$(run)"; then
  fail "missing claude did not fail the checkup: $out"
fi
grep -qi "FAIL.*claude" <<<"$out" || fail "missing claude not reported: $out"

echo "agent-checkup smoke tests passed"
