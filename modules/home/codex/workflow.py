"""Local delegation guards. No model calls, task inspection, or outcome tracking."""

from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat

MAX_DELEGATIONS = 4
SPAWN_TOOLS = {"spawn_agent", "Agent", "collaborationspawn_agent"}
SESSION_CONTEXT = (
    "Native codex-auto session. Bounded delegation is enabled under the installed "
    "Codex Global Instructions. Keep small or sequential tasks in the main session. "
    "For substantial independent work, use at most two task agents plus one focused "
    "reviewer; these are ceilings, not targets. No more than four delegated tasks "
    "per user turn; no nested delegation. Choose model and effort explicitly for "
    "independent assignments using the native workflow starting policy; manual "
    "choices win. Keep required tests, architect checkpoints, and permission scope. "
    "Use the normal integration review to notice costly repairs or escalation; "
    "do not add monitoring agents or duplicate runs merely to score model choices."
)


def state_root():
    base = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    if not base.is_absolute():
        raise ValueError("state directory must be absolute")
    return base / "codex-auto"


def key(value):
    return hashlib.sha256(value.encode()).hexdigest()


def private_directory(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("insecure delegation state directory")


@contextmanager
def counters(session, turn):
    root = state_root()
    private_directory(root)
    path = root / (key(session + "\0" + turn) + ".json")
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise ValueError("insecure delegation state file")
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        with os.fdopen(fd, "r+", encoding="utf-8", closefd=False) as handle:
            raw = handle.read(1025)
            calls = json.loads(raw) if raw else []
            if (len(raw) > 1024 or not isinstance(calls, list)
                    or len(calls) > MAX_DELEGATIONS
                    or not all(isinstance(call, str) and len(call) == 64 for call in calls)):
                raise ValueError("invalid delegation state")
            yield calls
            handle.seek(0)
            json.dump(calls, handle)
            handle.truncate()
            handle.flush()
    finally:
        os.close(fd)


def deny(reason):
    return {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}


def handle(event):
    if not isinstance(event, dict):
        return {}
    if event.get("hook_event_name") == "SessionStart":
        return {"hookSpecificOutput": {
            "hookEventName": "SessionStart", "additionalContext": SESSION_CONTEXT,
        }}
    if event.get("hook_event_name") != "PreToolUse" or event.get("tool_name") not in SPAWN_TOOLS:
        return {}
    if event.get("agent_id"):
        return deny("Nested delegation is disabled in codex-auto sessions.")
    identifiers = [event.get(field) for field in ("session_id", "turn_id", "tool_use_id")]
    if not all(isinstance(value, str) and 0 < len(value) <= 200 and "\0" not in value for value in identifiers):
        return deny("Delegation identifiers are unavailable; continue in the main agent.")
    session, turn, call = identifiers
    try:
        with counters(session, turn) as calls:
            call = key(call)
            if call in calls:
                return {}
            if len(calls) >= MAX_DELEGATIONS:
                return deny("Four-task delegation budget reached; continue in the main agent.")
            calls.append(call)
    except (OSError, ValueError):
        return deny("Local delegation budget could not be verified; continue in the main agent.")
    # Leave model, effort, sandbox, and native approval decisions untouched.
    return {}
