#!/usr/bin/env bash
set -euo pipefail

# Verifies the `cl` Claude Code launcher (shared/zsh/aliases.zsh, delegating
# to shared/bin/claude-launch): it forces a remote-control session whose title
# is "<host> / <dir>" so each device is identifiable, passes extra args
# through, and yields to an explicit --name.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "cl wrapper smoke test failed: $*" >&2
  exit 1
}

# run <host> <projname> [cl args...] -> prints the args `cl` passed to claude.
run() {
  local host="$1" proj="$2"
  shift 2
  local base dir log stub
  base="$(mktemp -d)"
  dir="$base/$proj"
  stub="$base/stub-bin"
  mkdir -p "$dir" "$stub"
  log="$base/log"

  # Stub `claude` as a PATH executable so the launcher records its argv
  # without launching anything (cl delegates to a bash script, so a zsh
  # function stub would not be seen); run from $dir so the title's directory
  # part resolves to <projname>.
  cat > "$stub/claude" <<'STUB'
#!/usr/bin/env bash
echo "claude $*" >> "$CL_LOG"
STUB
  chmod +x "$stub/claude"

  CL_LOG="$log" CL_DIR="$dir" CL_STUB="$stub" DOTFILES_HOST="$host" \
    DOTFILES_DIR="$ROOT" zsh -c '
    export PATH="$CL_STUB:$PATH"
    cd "$CL_DIR"
    source "$DOTFILES_DIR/shared/zsh/aliases.zsh"
    cl "$@"
  ' cl-smoke "$@"

  cat "$log"
  rm -rf "$base"
}

# Default launch: always-on remote control with a "<host> / <dir>" title.
# The wsl-desktop host maps to the curated device name "desktop".
out="$(run wsl-desktop dotfiles)"
grep -qF -- '--dangerously-skip-permissions' <<<"$out" || fail "missing --dangerously-skip-permissions: $out"
grep -qF -- '--remote-control' <<<"$out" || fail "missing --remote-control: $out"
grep -qF -- '--name desktop / dotfiles' <<<"$out" || fail "missing device/folder title: $out"

# Extra args pass through and the title reflects host + directory.
out="$(run minipc myproj --model opus)"
grep -qF -- '--name minipc / myproj' <<<"$out" || fail "title wrong with passthrough: $out"
grep -qF -- '--model opus' <<<"$out" || fail "passthrough arg dropped: $out"

# An explicit --name from the caller wins; no injected title.
out="$(run wsl-desktop dotfiles --name custom)"
grep -qF -- '--name custom' <<<"$out" || fail "explicit --name dropped: $out"
if grep -qF -- 'desktop /' <<<"$out"; then
  fail "injected title despite explicit --name: $out"
fi

# An explicit -n short flag wins too.
out="$(run pi scripts -n short)"
grep -qF -- '-n short' <<<"$out" || fail "explicit -n dropped: $out"
if grep -qF -- 'pi /' <<<"$out"; then
  fail "injected title despite explicit -n: $out"
fi

echo "cl wrapper smoke tests passed"
