#!/usr/bin/env bash
set -euo pipefail

# Verifies the claude-worker lifecycle manager (hosts/wsl-desktop/bin/
# claude-worker) against a stubbed tmux: session naming (cw-<name>), worker
# title labels
# (worker:<name>), state/meta recording, send/read/stop/restart command
# construction, and input validation. Nothing real is launched.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "claude-worker smoke test failed: $*" >&2
  exit 1
}

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
stub="$base/stub-bin"
proj="$base/myproj"
state="$base/state"
tmux_log="$base/tmux.log"
mkdir -p "$stub" "$proj"

# Stub tmux: records argv; `has-session` succeeds iff $TMUX_STUB_ALIVE exists;
# `load-buffer` drains stdin like the real thing.
cat > "$stub/tmux" <<'STUB'
#!/usr/bin/env bash
echo "tmux $*" >> "$TMUX_STUB_LOG"
case "$1" in
  has-session) [[ -e "$TMUX_STUB_ALIVE" ]] ;;
  load-buffer) cat > /dev/null ;;
esac
STUB
# Stub claude so the launcher prerequisite check passes.
printf '#!/usr/bin/env bash\n' > "$stub/claude"
chmod +x "$stub/tmux" "$stub/claude"

# run [args...] -> runs claude-worker with the stubbed environment.
run() {
  TMUX_STUB_LOG="$tmux_log" TMUX_STUB_ALIVE="$base/alive" \
    CLAUDE_WORKERS_STATE="$state" CLAUDE_WORKER_SEND_DELAY=0 \
    PATH="$stub:$PATH" "$ROOT/hosts/wsl-desktop/bin/claude-worker" "$@"
}

# --- start: tmux session, worker label, pipe-pane log, meta -------------------
run start impl --dir "$proj" >/dev/null
grep -qE -- "new-session -d -s cw-impl -c $proj .*claude-launch.*--label worker:impl" "$tmux_log" \
  || fail "start built wrong new-session: $(cat "$tmux_log")"
# The CLAUDE_WORKER marker lets hooks (e.g. the Discord todo relay) tell
# orchestrated workers apart from manual sessions.
grep -q -- "CLAUDE_WORKER=impl" "$tmux_log" || fail "start did not mark the worker env"
grep -q -- "pipe-pane" "$tmux_log" || fail "start did not enable pipe-pane logging"
[[ -f "$state/impl/meta" ]] || fail "start wrote no meta file"
grep -qx "dir=$proj" "$state/impl/meta" || fail "meta missing dir: $(cat "$state/impl/meta")"
grep -qx "session=cw-impl" "$state/impl/meta" || fail "meta missing session"
grep -qx "label=worker:impl" "$state/impl/meta" || fail "meta missing label"

# --- start refuses while the worker is already running ------------------------
touch "$base/alive"
run start impl --dir "$proj" >/dev/null 2>&1 && fail "double start unexpectedly succeeded"

# --- invalid worker names are rejected ----------------------------------------
run start "bad name" >/dev/null 2>&1 && fail "invalid name unexpectedly accepted"
run start "../escape" >/dev/null 2>&1 && fail "path-like name unexpectedly accepted"

# --- send: bracketed paste then Enter, exact-match target ----------------------
: > "$tmux_log"
run send impl "do the thing"
grep -q -- "load-buffer" "$tmux_log" || fail "send did not stage a buffer"
grep -q -- "paste-buffer -p" "$tmux_log" || fail "send did not use bracketed paste"
grep -q -- "send-keys -t =cw-impl Enter" "$tmux_log" || fail "send did not submit with Enter"
paste_line="$(grep -n -- 'paste-buffer' "$tmux_log" | cut -d: -f1)"
enter_line="$(grep -n -- 'send-keys' "$tmux_log" | cut -d: -f1)"
[[ "$paste_line" -lt "$enter_line" ]] || fail "Enter sent before paste"

# --- send reads stdin with '-' --------------------------------------------------
: > "$tmux_log"
printf 'line1\nline2\n' | run send impl -
grep -q -- "paste-buffer -p" "$tmux_log" || fail "stdin send did not paste"

# --- read: capture-pane on the exact session -----------------------------------
: > "$tmux_log"
# shellcheck disable=SC2162  # claude-worker's read subcommand, not the builtin
run read impl 40 >/dev/null
grep -q -- "capture-pane -p -t =cw-impl -S -40" "$tmux_log" || fail "read built wrong capture-pane: $(cat "$tmux_log")"

# --- status/list run and report the worker -------------------------------------
run status impl | grep -q "running: yes" || fail "status did not report running"
run list | grep -q "impl" || fail "list did not show worker"

# --- stop: exact-match kill-session ---------------------------------------------
: > "$tmux_log"
run stop impl >/dev/null
grep -q -- "kill-session -t =cw-impl" "$tmux_log" || fail "stop built wrong kill-session"

# --- restart: reuses the recorded dir -------------------------------------------
rm -f "$base/alive"
: > "$tmux_log"
run restart impl >/dev/null
grep -qE -- "new-session -d -s cw-impl -c $proj " "$tmux_log" || fail "restart lost the recorded dir: $(cat "$tmux_log")"

# --- commands on unknown/stopped workers fail cleanly ---------------------------
run send nosuch hi >/dev/null 2>&1 && fail "send to unknown worker unexpectedly succeeded"
run restart nosuch >/dev/null 2>&1 && fail "restart of unknown worker unexpectedly succeeded"

echo "claude-worker smoke tests passed"
