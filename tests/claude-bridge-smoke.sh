#!/usr/bin/env bash
set -euo pipefail

# Verifies claude-bridge's pure helpers (hosts/wsl-desktop/agent-bridge/bin/claude-bridge)
# with plain python3 — no discord.py, no network, nothing launched: Discord
# message splitting, transcript reply extraction, HMAC verification, config
# round-trips, the fresh-start markers, and chat-target parsing. (The slash
# commands themselves are discord.py interactions, exercised live.)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# PYTHONDONTWRITEBYTECODE: importing the script must not drop a __pycache__
# into hosts/wsl-desktop/agent-bridge/bin (repository-smoke checks executability there).
BRIDGE="$ROOT/hosts/wsl-desktop/agent-bridge/bin/claude-bridge" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
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

# --- channel-purge confirmation suffix (/clear, /fresh cleanup) -----------------------
assert b.purge_suffix(0) == "", "clean run, nothing deleted -> no suffix"
assert b.purge_suffix(1) == " — cleared 1 message", "singular deleted count"
assert b.purge_suffix(5) == " — cleared 5 messages", "plural deleted count"
sfx = b.purge_suffix(0, "bot needs the **Manage Messages** permission to clean up")
assert sfx.startswith(" — couldn't clear the channel:"), f"blocker with 0 deleted: {sfx!r}"
assert "Manage Messages" in sfx, "blocker note lost"
sfx2 = b.purge_suffix(3, "some messages couldn't be deleted")
assert "cleared 3 messages, but some messages" in sfx2, f"partial-fail wording: {sfx2!r}"

# --- chat target parsing --------------------------------------------------------------
assert b.channel_from_chat("discord:123") == 123
assert b.channel_from_chat("discord:123:456") == 123
assert b.channel_from_chat("discord") is None
assert b.channel_from_chat("slack:99") is None
assert b.channel_from_chat("") is None

# --- per-channel guest authorization --------------------------------------------------
gcfg = {"allowed_users": [1], "repos": {
    "100": {"name": "orch", "dir": "/x"},                                    # owner-only
    "200": {"name": "cal", "dir": "/y", "guests": [2], "profile": "utility"},
}}
assert b.channel_allows(gcfg, 100, 1), "owner should talk in any channel"
assert b.channel_allows(gcfg, 200, 1), "owner should talk in a guest channel too"
assert b.channel_allows(gcfg, 200, 2), "guest should talk in their own channel"
assert not b.channel_allows(gcfg, 100, 2), "guest must NOT talk in another channel"
assert not b.channel_allows(gcfg, 200, 3), "stranger blocked in a guest channel"
assert not b.channel_allows(gcfg, 999, 2), "guest blocked in an unmapped channel"
assert b.channel_allows(gcfg, 999, 1), "owner allowed even in an unmapped channel (caller no-ops without a repo)"

# --- capability profiles -> claude launch flags ---------------------------------------
assert b.profile_args("owner") == [], "owner profile adds no flags"
assert b.profile_args(None) == [], "missing profile is owner"
u = b.profile_args("utility", "/pdir")
assert "--enforce-perms" in u, "utility must enforce permissions (not bypass)"
assert "--tools" in u and u[u.index("--tools") + 1] == "", "utility must disable built-in tools"
assert "--strict-mcp-config" in u, "utility must pin the MCP set"
assert "/pdir/utility.mcp.json" in u, "utility must load its own mcp config"
assert "--allowedTools" in u and any(x.startswith("mcp__") for x in u), "utility must pre-approve its MCP tools"
assert "/pdir/utility.settings.json" in u, "utility must load its settings guardrails"
c = b.profile_args("collab", "/pdir")
assert "--enforce-perms" in c, "collab must enforce permissions (not bypass)"
assert "--settings" in c and "/pdir/collab.settings.json" in c, "collab must load its deny-guardrail settings"
assert "--tools" not in c, "collab keeps built-in dev tools"
# owner keeps the frictionless default (no enforce flag)
assert "--enforce-perms" not in b.profile_args("owner"), "owner stays on the fast path"

# --- start_args threads the profile in AND still injects the Discord protocol ---------
pa = b.start_args("cal", "/y", 200, resume=False, profile="utility")
assert "--tools" in pa and "--append-system-prompt" in pa, "profiled start lost flags or protocol"
assert pa.index("--tools") > pa.index("--"), "profile flags must follow the -- separator"
assert b.start_args("orch", "/x", 100, resume=False) == b.start_args("orch", "/x", 100, resume=False, profile="owner"), \
    "default profile must equal owner (backward compatible)"

# --- config round-trip preserves guests + profile -------------------------------------
with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "config.json")
    gc = b.load_config(path)
    gc["repos"]["200"] = {"name": "cal", "dir": "/y", "guests": [2], "profile": "utility"}
    b.save_config(gc, path)
    rc = b.load_config(path)
    assert rc["repos"]["200"]["guests"] == [2], "guests lost in round-trip"
    assert rc["repos"]["200"]["profile"] == "utility", "profile lost in round-trip"

# --- the public #welcome channel is open to anyone in the gate ------------------------
wcfg = {"allowed_users": [1], "welcome_channel": "500",
        "repos": {"500": {"name": "welcome", "dir": "/w"}}}
assert b.channel_allows(wcfg, 500, 999), "anyone may talk in #welcome"
assert b.channel_allows(wcfg, 500, 1), "owner may talk in #welcome too"
assert not b.channel_allows(wcfg, 501, 999), "a stranger stays blocked outside #welcome"

# --- greeter profile: empty MCP set + its settings, keeps Bash for bridge-ctl ---------
gp = b.profile_args("greeter", "/pdir")
assert "--enforce-perms" in gp, "greeter must enforce permissions (a public worker must not bypass)"
assert "--strict-mcp-config" in gp and "/pdir/greeter.mcp.json" in gp, "greeter must pin an empty MCP set"
assert "/pdir/greeter.settings.json" in gp, "greeter must load its settings"
assert "--tools" not in gp, "greeter keeps built-in tools (it runs bridge-ctl via Bash)"

# --- the welcome worker gets the greeter brief, not the push-first protocol ------------
assert b.system_prompt("welcome") == b.GREETER, "welcome worker must get the greeter brief"
assert b.GREETER != b.PROTOCOL, "greeter brief must differ from the Ned protocol"
assert "bridge-ctl request" in b.GREETER, "greeter brief missing the request command"
wa = b.start_args("welcome", "/w", 500, resume=False, profile="greeter")
assert "--strict-mcp-config" in wa and "--append-system-prompt" in wa, "welcome start lost flags/brief"

# --- access-request card round-trips through its marker -------------------------------
card = b.format_request_card(656, "photo-pipeline", "wants to help with exports")
assert "photo-pipeline" in card and "<@656>" in card, "card missing project/mention"
assert b.parse_request_marker(card) == (656, "photo-pipeline"), "marker did not round-trip"
assert b.parse_request_marker("just a normal message") is None, "false-positive marker parse"
# a resolved card (headline only, marker stripped) must not re-fire
assert b.parse_request_marker(card.split("\n\n")[0]) is None, "resolved card should not parse"

print("ok")
PY

echo "claude-bridge smoke tests passed"
