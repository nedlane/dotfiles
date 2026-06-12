#!/usr/bin/env bash
set -euo pipefail

# Verifies the standalone claude-launch launcher (shared/bin/claude-launch):
# it forces an interactive remote-control session titled "<host> / <dir>"
# (or "<host> / <label>" with --label), yields to an explicit --name/-n,
# resolves the host from $DOTFILES_HOST or the linker's recorded host file,
# and strips API/provider billing env vars so a calling environment can never
# flip Claude Code off the interactive subscription auth path.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "claude-launch smoke test failed: $*" >&2
  exit 1
}

# run <projname> [env VAR=...] -- [claude-launch args...]
# Prints what the stubbed `claude` received: its argv plus the visibility of
# each forbidden env var.
run() {
  local proj="$1"
  shift
  local base dir log stub
  base="$(mktemp -d)"
  dir="$base/$proj"
  stub="$base/stub-bin"
  log="$base/log"
  mkdir -p "$dir" "$stub"

  cat > "$stub/claude" <<'STUB'
#!/usr/bin/env bash
{
  echo "claude $*"
  echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-unset}"
  echo "CLAUDE_CODE_USE_BEDROCK=${CLAUDE_CODE_USE_BEDROCK:-unset}"
} >> "$CL_LOG"
STUB
  chmod +x "$stub/claude"

  local envs=()
  while [[ "${1:-}" != "--" ]]; do
    envs+=("$1")
    shift
  done
  shift

  (
    cd "$dir"
    env "${envs[@]}" CL_LOG="$log" PATH="$stub:$PATH" \
      "$ROOT/shared/bin/claude-launch" "$@" 2>/dev/null
  )
  cat "$log"
  rm -rf "$base"
}

# Default launch: remote control titled "<host> / <dir>"; wsl-desktop maps to
# the curated device name "desktop".
out="$(run dotfiles DOTFILES_HOST=wsl-desktop --)"
grep -qF -- '--dangerously-skip-permissions' <<<"$out" || fail "missing --dangerously-skip-permissions: $out"
grep -qF -- '--remote-control' <<<"$out" || fail "missing --remote-control: $out"
grep -qF -- '--name desktop / dotfiles' <<<"$out" || fail "missing device/folder title: $out"

# --label replaces the directory part of the title (worker naming contract).
out="$(run dotfiles DOTFILES_HOST=wsl-desktop -- --label worker:impl)"
grep -qF -- '--name desktop / worker:impl' <<<"$out" || fail "missing worker label title: $out"
grep -qF -- 'dotfiles' <<<"$out" && fail "dir leaked into labeled title: $out"

# Extra args pass through alongside the injected title.
out="$(run myproj DOTFILES_HOST=minipc -- --model opus)"
grep -qF -- '--name minipc / myproj' <<<"$out" || fail "title wrong with passthrough: $out"
grep -qF -- '--model opus' <<<"$out" || fail "passthrough arg dropped: $out"

# An explicit --name from the caller wins; no injected title.
out="$(run dotfiles DOTFILES_HOST=wsl-desktop -- --name custom)"
grep -qF -- '--name custom' <<<"$out" || fail "explicit --name dropped: $out"
grep -qF -- 'desktop /' <<<"$out" && fail "injected title despite explicit --name: $out"

# An explicit -n short flag wins too.
out="$(run scripts DOTFILES_HOST=pi -- -n short)"
grep -qF -- '-n short' <<<"$out" || fail "explicit -n dropped: $out"
grep -qF -- 'pi /' <<<"$out" && fail "injected title despite explicit -n: $out"

# Without $DOTFILES_HOST (non-interactive shells), the host comes from the
# linker's recorded host file.
cfg="$(mktemp -d)"
mkdir -p "$cfg/dotfiles"
printf 'minipc2\n' > "$cfg/dotfiles/host"
out="$(run proj DOTFILES_HOST= XDG_CONFIG_HOME="$cfg" --)"
grep -qF -- '--name minipc2 / proj' <<<"$out" || fail "host file fallback broken: $out"
rm -rf "$cfg"

# API/provider billing env vars are stripped before claude starts.
out="$(run proj DOTFILES_HOST=pi ANTHROPIC_API_KEY=leaked CLAUDE_CODE_USE_BEDROCK=1 --)"
grep -qF -- 'ANTHROPIC_API_KEY=unset' <<<"$out" || fail "ANTHROPIC_API_KEY leaked through: $out"
grep -qF -- 'CLAUDE_CODE_USE_BEDROCK=unset' <<<"$out" || fail "CLAUDE_CODE_USE_BEDROCK leaked through: $out"

echo "claude-launch smoke tests passed"
