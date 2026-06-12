#!/usr/bin/env bash
set -euo pipefail

# Verifies claude-bridge's pure helpers (hosts/wsl-desktop/bin/claude-bridge)
# with plain python3 — no discord.py, no network, nothing launched: command
# parsing, Discord message splitting, transcript reply extraction, HMAC
# verification, config round-trips, and chat-target parsing.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# PYTHONDONTWRITEBYTECODE: importing the script must not drop a __pycache__
# into hosts/wsl-desktop/bin (repository-smoke checks executability there).
BRIDGE="$ROOT/hosts/wsl-desktop/bin/claude-bridge" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import hashlib, hmac, importlib.util, json, os, sys, tempfile

spec = importlib.util.spec_from_file_location(
    "claude_bridge", os.environ["BRIDGE"],
    loader=importlib.machinery.SourceFileLoader("claude_bridge", os.environ["BRIDGE"]),
)
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)

def fail(msg):
    print(f"claude-bridge smoke test failed: {msg}", file=sys.stderr)
    sys.exit(1)

# --- command parsing ---------------------------------------------------------
assert b.parse_command("!addrepo ghpr ~/projects/ghpr") == ("addrepo", ["ghpr", "~/projects/ghpr"]), "addrepo parse"
assert b.parse_command("!STATUS") == ("status", []), "case-insensitive command"
assert b.parse_command("hello world") is None, "plain text is not a command"
assert b.parse_command("!!") is None, "garbage bang is not a command"
assert b.parse_command("") is None, "empty text"

# --- message splitting ---------------------------------------------------------
short = b.split_message("hello\nworld")
assert short == ["hello\nworld"], f"short message split: {short}"
lines = "\n".join(f"line {i:04d} " + "x" * 60 for i in range(80))
chunks = b.split_message(lines)
assert len(chunks) > 1, "long message did not split"
assert all(len(c) <= 2000 for c in chunks), "chunk exceeds Discord limit"
assert all(c.startswith("line") for c in chunks), "split mid-line"
mono = "y" * 5000
chunks = b.split_message(mono)
assert all(len(c) <= 2000 for c in chunks), "pathological line not split"
huge = "z\n" * 10000
chunks = b.split_message(huge)
assert "truncated" in chunks[-1], "oversized reply not truncated with a note"

# --- transcript extraction -------------------------------------------------------
with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
    f.write(json.dumps({"type": "user", "message": {"content": "do it"}}) + "\n")
    f.write(json.dumps({"type": "assistant", "message": {"content": [
        {"type": "text", "text": "working on it"}]}}) + "\n")
    f.write("not json\n")
    f.write(json.dumps({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": "Bash"}]}}) + "\n")
    f.write(json.dumps({"type": "assistant", "message": {"content": [
        {"type": "text", "text": "All done."}, {"type": "text", "text": "Tests pass."}]}}) + "\n")
    path = f.name
reply = b.extract_last_reply(path)
os.unlink(path)
assert reply == "All done.\nTests pass.", f"wrong reply extracted: {reply!r}"
assert b.extract_last_reply("/nonexistent/file") == "", "missing transcript not empty"

# --- incremental extraction (the one-prompt-behind fix) ---------------------------
def entry(text):
    return json.dumps({"type": "assistant", "message": {"content": [
        {"type": "text", "text": text}]}}) + "\n"

with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
    f.write(entry("reply one"))
    path = f.name
reply, off = b.extract_new_reply(path, 0)
assert reply == "reply one", f"first incremental read wrong: {reply!r}"
# Stale read after consuming everything: empty, offset unchanged.
reply2, off2 = b.extract_new_reply(path, off)
assert reply2 == "" and off2 == off, "stale read returned old reply (one-prompt-behind)"
# A mid-write partial line is not consumed...
with open(path, "a") as f:
    f.write(entry("reply two")[: 25])
reply3, off3 = b.extract_new_reply(path, off)
assert reply3 == "" and off3 == off, "partial line consumed or misread"
# ...and is picked up once complete.
with open(path, "a") as f:
    f.write(entry("reply two")[25:])
reply4, off4 = b.extract_new_reply(path, off)
assert reply4 == "reply two" and off4 > off, f"completed line not picked up: {reply4!r}"
os.unlink(path)

# --- HMAC verification ------------------------------------------------------------
body = b'{"event_type": "claude.worker.turn_ended"}'
sig = hmac.new(b"s3cret", body, hashlib.sha256).hexdigest()
assert b.verify_signature(body, sig, "s3cret"), "valid signature rejected"
assert not b.verify_signature(body, sig, "wrong"), "wrong secret accepted"
assert not b.verify_signature(body, "", "s3cret"), "empty signature accepted"
assert not b.verify_signature(body, sig, ""), "empty secret accepted"

# --- config round-trip (the !addrepo mutation) --------------------------------------
with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "cfg", "config.json")
    cfg = b.load_config(path)
    assert cfg["idle_minutes"] == 45, "default idle_minutes"
    cfg["repos"]["123"] = {"name": "ghpr", "dir": "/home/u/projects/ghpr"}
    b.save_config(cfg, path)
    cfg2 = b.load_config(path)
    assert cfg2["repos"]["123"]["name"] == "ghpr", "repo mapping lost in round-trip"

# --- missing binaries surface as failed results, not exceptions ------------------------
r = b._run(["definitely-not-a-real-command-xyz"])
assert r.returncode == 127, "missing command did not yield rc 127"
assert "definitely-not-a-real-command-xyz" in r.stderr, "missing-command error lost"

# --- chat target parsing --------------------------------------------------------------
assert b.channel_from_chat("discord:123") == 123
assert b.channel_from_chat("discord:123:456") == 123
assert b.channel_from_chat("discord") is None
assert b.channel_from_chat("slack:99") is None
assert b.channel_from_chat("") is None

print("ok")
PY

echo "claude-bridge smoke tests passed"
