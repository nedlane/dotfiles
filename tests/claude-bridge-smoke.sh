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

# --- worker start args inject the Discord protocol -------------------------------------
args = b.start_args("ghpr", "/home/u/projects/ghpr", 123, resume=False)
assert args[:3] == ["claude-worker", "start", "ghpr"], f"bad start argv: {args}"
assert "--chat" in args and "discord:123" in args, "chat target missing"
assert "--append-system-prompt" in args, "protocol not injected"
proto = args[args.index("--append-system-prompt") + 1]
assert "discord-notify" in proto, "protocol does not mention discord-notify"
assert "check-in" in proto, "protocol does not cover check-ins"
assert "--continue" not in args, "fresh start should not --continue"
args = b.start_args("ghpr", "/x", 123, resume=True)
assert "--continue" in args and args.index("--continue") > args.index("--"), "resume flag misplaced"

# --- !fresh: shut down + fresh next start (arm marker, one-shot, no resume) ------------
assert b.should_resume(True, False) is True, "state, no fresh armed -> resume"
assert b.should_resume(True, True) is False, "fresh armed -> must not resume"
assert b.should_resume(False, False) is False, "no state -> nothing to resume"
assert b.should_resume(False, True) is False, "no state, fresh armed -> fresh"
with tempfile.TemporaryDirectory() as d:
    assert not b.fresh_pending("w", d), "unarmed worker should not be pending"
    b.disarm_fresh("w", d)  # idempotent even when nothing/no dir exists
    b.arm_fresh("w", d)     # creates the worker dir if absent
    assert b.fresh_pending("w", d), "arm_fresh did not arm"
    assert os.path.isfile(os.path.join(d, "w", "no-resume")), "marker file missing"
    # A stopped worker keeps state; the marker must coexist with meta.
    open(os.path.join(d, "w", "meta"), "w").close()
    assert b.should_resume(b.worker_has_state("w", d), b.fresh_pending("w", d)) is False, \
        "armed fresh must override saved state"
    b.disarm_fresh("w", d)
    assert not b.fresh_pending("w", d), "disarm_fresh did not clear the marker"
    assert b.should_resume(b.worker_has_state("w", d), b.fresh_pending("w", d)) is True, \
        "after disarm, saved state should resume again"

# --- the orchestrator worker gets the control-plane brief on top ------------------------
assert b.system_prompt("ghpr") == b.PROTOCOL, "plain worker prompt should be PROTOCOL only"
orch = b.system_prompt("orchestrator")
assert orch.startswith(b.PROTOCOL), "orchestrator lost the base protocol"
assert "bridge-ctl start" in orch, "orchestrator brief missing bridge-ctl start"
assert "claude-worker send" in orch, "orchestrator brief missing claude-worker send"
args = b.start_args("orchestrator", "/home/u", 9, resume=False)
assert "ORCHESTRATOR" in args[args.index("--append-system-prompt") + 1], \
    "start_args did not inject the orchestrator brief"

# --- missing binaries surface as failed results, not exceptions ------------------------
r = b._run(["definitely-not-a-real-command-xyz"])
assert r.returncode == 127, "missing command did not yield rc 127"
assert "definitely-not-a-real-command-xyz" in r.stderr, "missing-command error lost"

# --- readiness gating (don't paste the waking message into a loading TUI) -------------
assert b.screen_is_ready("> done\n❯ \n"), "idle prompt should be ready"
assert not b.screen_is_ready("loading...\n"), "no prompt is not ready"
assert not b.screen_is_ready("working\nesc to interrupt\n❯ \n"), "busy turn is not ready"
assert not b.screen_is_ready("Compacting conversation…\n❯ \n"), "compaction is not ready"
assert not b.screen_is_ready(
    "Do you trust the files in this folder?\n❯ 1. Yes\n"
), "trust dialog is not ready"
assert not b.screen_is_ready(
    "❯ 1. Resume from summary (recommended)\n  2. Resume full session as-is\n"
), "resume-mode dialog is not ready"

# --- inbound tagging (remind workers to reply on Discord) -----------------------------
tagged = b.tag_inbound("ship it", typed=False)
assert tagged.endswith("\n\nship it"), f"message body lost: {tagged!r}"
assert "discord-notify" in tagged, "tag does not mention discord-notify"
assert b.DISCORD_TAG in tagged, "tag constant not applied"
assert b.tag_inbound("/compact", typed=True) == "/compact", "slash command must pass through untouched"
assert b.tag_inbound("", typed=False) == "", "empty body should not be tagged"
assert b.tag_inbound("   ", typed=False) == "   ", "whitespace-only body should not be tagged"

# --- inbound composition: reply quote + text + attachment footer ----------------------
assert b.compose_inbound("hi", None, None) == "hi", "plain text should pass through"
ci = b.compose_inbound("look at this", ["/inbox/1-a.png"], None)
assert "look at this" in ci and "/inbox/1-a.png" in ci, "attachment path/text lost"
assert "attached 1 file" in ci, "singular attachment wording"
ci2 = b.compose_inbound("", ["/x/a", "/x/b"], None)
assert "attached 2 files" in ci2 and "/x/a" in ci2 and "/x/b" in ci2, "multi-attachment footer"
ci3 = b.compose_inbound("do it", None, "the earlier question")
assert ci3.startswith("(replying to: the earlier question)"), "reply quote must lead"
assert "do it" in ci3, "reply body lost"
assert b.compose_inbound("", None, None) == "", "nothing in, nothing out"

# --- edit framing + reply preview -----------------------------------------------------
assert b.compose_edit("new text").endswith("\n\nnew text"), "edit body lost"
assert "edited" in b.compose_edit("x"), "edit note doesn't say edited"
assert b.reply_preview("  hello\nworld  ") == "hello world", "preview should trim + flatten"
assert b.reply_preview("") is None, "empty preview is None"
assert b.reply_preview("   ") is None, "whitespace preview is None"
long_prev = b.reply_preview("x" * 250)
assert long_prev.endswith("…") and len(long_prev) == 201, "preview not capped at 200+ellipsis"

# --- chat target parsing --------------------------------------------------------------
assert b.channel_from_chat("discord:123") == 123
assert b.channel_from_chat("discord:123:456") == 123
assert b.channel_from_chat("discord") is None
assert b.channel_from_chat("slack:99") is None
assert b.channel_from_chat("") is None

print("ok")
PY

echo "claude-bridge smoke tests passed"
