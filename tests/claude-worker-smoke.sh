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

# Stub tmux: records argv; `has-session` succeeds iff $TMUX_STUB_ALIVE exists
# (and `new-session` creates it, like the real thing); `capture-pane` plays
# back $TMUX_STUB_SCREEN; `send-keys` advances to $TMUX_STUB_NEXT_SCREEN if
# one is staged (simulates dismissing a dialog); `load-buffer` drains stdin.
cat > "$stub/tmux" <<'STUB'
#!/usr/bin/env bash
echo "tmux $*" >> "$TMUX_STUB_LOG"
case "$1" in
  has-session)  [[ -e "$TMUX_STUB_ALIVE" ]] ;;
  new-session)  touch "$TMUX_STUB_ALIVE" ;;
  load-buffer)  cat > /dev/null ;;
  capture-pane) cat "$TMUX_STUB_SCREEN" 2>/dev/null ;;
  send-keys)
    if [[ -n "${TMUX_STUB_NEXT_SCREEN:-}" && -e "${TMUX_STUB_NEXT_SCREEN:-}" ]]; then
      mv "$TMUX_STUB_NEXT_SCREEN" "$TMUX_STUB_SCREEN"
    fi
    ;;
esac
STUB
# Stub claude so the launcher prerequisite check passes.
printf '#!/usr/bin/env bash\n' > "$stub/claude"
chmod +x "$stub/tmux" "$stub/claude"

# Default screen: an idle Claude prompt (start/wait consider this ready).
printf '> idle\n❯ \n' > "$base/screen"

# run [args...] -> runs claude-worker with the stubbed environment.
run() {
  TMUX_STUB_LOG="$tmux_log" TMUX_STUB_ALIVE="$base/alive" \
    TMUX_STUB_SCREEN="$base/screen" TMUX_STUB_NEXT_SCREEN="$base/next-screen" \
    CLAUDE_WORKERS_STATE="$state" CLAUDE_WORKER_SEND_DELAY=0 \
    CLAUDE_WORKER_POLL=0 CLAUDE_WORKER_START_TIMEOUT=3 \
    PATH="$stub:$PATH" "$ROOT/hosts/wsl-desktop/bin/claude-worker" "$@"
}

# --- start: tmux session, worker label, pipe-pane log, meta, blocks to ready --
out="$(run start impl --dir "$proj")" || fail "start failed: $out"
grep -q "state:  ready" <<<"$out" || fail "start did not block until ready: $out"
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

# --- send: bracketed paste then Enter (twice, for TUI race), exact target -------
: > "$tmux_log"
run send impl "do the thing"
grep -q -- "load-buffer" "$tmux_log" || fail "send did not stage a buffer"
grep -q -- "paste-buffer -p" "$tmux_log" || fail "send did not use bracketed paste"
[[ "$(grep -c -- "send-keys -t =cw-impl: Enter" "$tmux_log")" -ge 2 ]] \
  || fail "send did not double-Enter: $(cat "$tmux_log")"
paste_line="$(grep -n -- 'paste-buffer' "$tmux_log" | head -1 | cut -d: -f1)"
enter_line="$(grep -n -- 'send-keys' "$tmux_log" | head -1 | cut -d: -f1)"
[[ "$paste_line" -lt "$enter_line" ]] || fail "Enter sent before paste"

# --- send reads stdin with '-' --------------------------------------------------
: > "$tmux_log"
printf 'line1\nline2\n' | run send impl -
grep -q -- "paste-buffer -p" "$tmux_log" || fail "stdin send did not paste"

# --- read: capture-pane on the exact session -----------------------------------
: > "$tmux_log"
# shellcheck disable=SC2162  # claude-worker's read subcommand, not the builtin
run read impl 40 >/dev/null
grep -q -- "capture-pane -p -t =cw-impl: -S -40" "$tmux_log" || fail "read built wrong capture-pane: $(cat "$tmux_log")"

# --- status/list run and report the worker -------------------------------------
run status impl | grep -q "running: yes" || fail "status did not report running"
run list | grep -q "impl" || fail "list did not show worker"
# Meta-less state dirs (relay hash storage, stray mkdirs) are not workers.
mkdir -p "$state/not-a-worker"
run list | grep -q "not-a-worker" && fail "list showed a meta-less artifact dir"

# --- stop: exact-match kill-session ---------------------------------------------
: > "$tmux_log"
run stop impl >/dev/null
grep -q -- "kill-session -t =cw-impl" "$tmux_log" || fail "stop built wrong kill-session"

# --- restart: reuses the recorded dir -------------------------------------------
rm -f "$base/alive"
: > "$tmux_log"
run restart impl >/dev/null
grep -qE -- "new-session -d -s cw-impl -c $proj " "$tmux_log" || fail "restart lost the recorded dir: $(cat "$tmux_log")"

# --- wait: marker counts only once idle; busy workers time out -------------------
# While busy, the marker is ignored even if visible (the sent instruction
# echoes it on screen).
printf 'do X then print MARKER\nesc to interrupt\n❯ \n' > "$base/screen"
rc=0
run wait impl --for MARKER --timeout 1 >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "wait --for matched the echoed marker while busy (got $rc)"
rc=0
run wait impl --timeout 1 >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "wait on busy worker did not time out with exit 2 (got $rc)"
printf 'do X then print MARKER\nMARKER\n❯ \n' > "$base/screen"
run wait impl --for MARKER --timeout 5 >/dev/null || fail "wait --for missed marker on idle worker"
run wait impl --timeout 5 >/dev/null || fail "wait did not detect idle prompt"

# --- start auto-accepts the folder-trust dialog ----------------------------------
rm -f "$base/alive"
printf 'Do you trust the files in this folder?\n❯ 1. Yes, I trust this folder\n' > "$base/screen"
printf '> booted\n❯ \n' > "$base/next-screen"
out="$(run start trusty --dir "$proj")" || fail "start with trust dialog failed: $out"
grep -q "state:  ready" <<<"$out" || fail "trust dialog was not auto-accepted: $out"

# --- commands on unknown/stopped workers fail cleanly ---------------------------
rm -f "$base/alive"
run send nosuch hi >/dev/null 2>&1 && fail "send to unknown worker unexpectedly succeeded"
run restart nosuch >/dev/null 2>&1 && fail "restart of unknown worker unexpectedly succeeded"

echo "claude-worker smoke tests passed"
