#!/usr/bin/env bash
set -euo pipefail

# Verifies the control-plane readiness check (hosts/wsl-desktop/bin/
# agent-checkup) against a fully stubbed environment: subscription-auth
# detection for Codex and Claude Code, forbidden-env warnings, missing-tool
# failures, and that no secret values are echoed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKUP="$ROOT/hosts/wsl-desktop/bin/agent-checkup"

fail() {
  echo "agent-checkup smoke test failed: $*" >&2
  exit 1
}

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
home="$base/home"
stub="$base/stub-bin"
mkdir -p "$home/.codex" "$home/.claude" "$home/.local/state" "$stub"

for tool in codex claude tmux; do
  printf '#!/usr/bin/env bash\necho "%s 1.0.0"\n' "$tool" > "$stub/$tool"
  chmod +x "$stub/$tool"
done

cat > "$home/.codex/auth.json" <<'JSON'
{"OPENAI_API_KEY": null, "auth_mode": "chatgpt", "tokens": {"access_token": "sk-fake-secret-value"}}
JSON
printf '{"claudeAiOauth": {"accessToken": "fake-claude-secret"}}\n' > "$home/.claude/.credentials.json"

# run [env overrides...] -> runs agent-checkup in the stub environment.
run() {
  env -i HOME="$home" PATH="$stub:$ROOT/shared/bin:$ROOT/hosts/wsl-desktop/bin:/usr/bin:/bin" \
    "$@" "$CHECKUP" 2>&1
}

# --- healthy setup: exit 0, subscription auth detected on both sides -----------
out="$(run)" || fail "healthy environment reported failure: $out"
grep -q "PASS.*tmux" <<<"$out" || fail "missing tmux pass: $out"
grep -qi "PASS.*codex.*chatgpt\|PASS.*chatgpt.*codex" <<<"$out" || fail "codex subscription auth not detected: $out"
grep -qi "PASS.*claude.*interactive\|PASS.*interactive.*claude" <<<"$out" || fail "claude interactive auth not detected: $out"
grep -qi "manual" <<<"$out" || fail "no manual checks section: $out"

# Secret values from auth files must never be echoed.
grep -q "sk-fake-secret-value\|fake-claude-secret" <<<"$out" && fail "secret value leaked: $out"

# --- forbidden env vars are flagged ---------------------------------------------
out="$(run ANTHROPIC_API_KEY=x OPENAI_API_KEY=y)" || true
grep -qi "WARN.*ANTHROPIC_API_KEY" <<<"$out" || fail "ANTHROPIC_API_KEY not flagged: $out"
grep -qi "WARN.*OPENAI_API_KEY" <<<"$out" || fail "OPENAI_API_KEY not flagged: $out"

# --- API-key codex auth is flagged ----------------------------------------------
printf '{"OPENAI_API_KEY": "sk-real", "auth_mode": "apikey"}\n' > "$home/.codex/auth.json"
out="$(run)" || true
grep -qi "WARN.*codex" <<<"$out" || fail "API-key codex auth not flagged: $out"
cat > "$home/.codex/auth.json" <<'JSON'
{"OPENAI_API_KEY": null, "auth_mode": "chatgpt", "tokens": {"access_token": "sk-fake-secret-value"}}
JSON

# --- a missing tool is a FAIL with non-zero exit ---------------------------------
rm "$stub/codex"
if out="$(run)"; then
  fail "missing codex did not fail the checkup: $out"
fi
grep -qi "FAIL.*codex" <<<"$out" || fail "missing codex not reported: $out"

echo "agent-checkup smoke tests passed"
