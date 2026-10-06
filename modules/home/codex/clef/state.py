"""Private, locked metadata storage. No prompts, tool arguments, or outputs."""

from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import uuid

from .client import ClefError, private_read


EVENTS = {
    "route",
    "approval",
    "workflow",
    "completion",
    "escalation",
    "vision",
    "outcome",
    "session",
}
FIELDS = {
    "event",
    "decision_id",
    "session",
    "policy_version",
    "provider",
    "mode",
    "status",
    "selected_model",
    "selected_effort",
    "probability",
    "confidence",
    "margin",
    "latency_ms",
    "input_tokens",
    "output_tokens",
    "applied",
    "fallback_reason",
    "decision",
    "test_outcome",
    "human_agreement",
    "escalated",
    "duration_ms",
}


def state_root() -> Path:
    base = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    if not base.is_absolute():
        raise ClefError("invalid_state_home")
    return base / "codex-clef"


def session_key(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()[:24]


def ensure_private_dir(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if (
        not stat.S_ISDIR(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_mode & 0o077
    ):
        raise ClefError("insecure_state_directory")


@contextmanager
def locked(path: Path):
    ensure_private_dir(path.parent)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
        ):
            raise ClefError("insecure_state_file")
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        with os.fdopen(fd, "r+", encoding="utf-8", closefd=False) as handle:
            yield handle
    finally:
        os.close(fd)


class Store:
    def __init__(self, root: Path | None = None):
        self.root = root or state_root()

    def log(self, **fields) -> str:
        if set(fields) - FIELDS or fields.get("event") not in EVENTS:
            raise ClefError("invalid_log_fields")
        # Call sites must use enums, internal IDs and numeric metadata only.
        for key, value in fields.items():
            if isinstance(value, str) and (
                len(value) > 120 or any(c.isspace() for c in value)
            ):
                raise ClefError("invalid_log_value")
            if value is not None and type(value) not in (str, int, float, bool):
                raise ClefError("invalid_log_value")
        fields.setdefault("decision_id", uuid.uuid4().hex)
        fields["timestamp"] = datetime.now(timezone.utc).isoformat()
        record = json.dumps(fields, separators=(",", ":"), allow_nan=False)
        with locked(self.root / "decisions.jsonl") as handle:
            handle.seek(0, 2)
            # Bound local storage without deleting historical Jev data.
            if handle.tell() > 10_000_000:
                raise ClefError("log_full")
            handle.write(record + "\n")
            handle.flush()
        return fields["decision_id"]

    @contextmanager
    def counters(self, session: str):
        ensure_private_dir(self.root)
        path = self.root / "sessions" / (session_key(session) + ".json")
        with locked(path) as handle:
            raw = handle.read(32769)
            if len(raw) > 32768:
                raise ClefError("state_too_large")
            try:
                data = json.loads(raw) if raw else {}
            except ValueError:
                raise ClefError("invalid_state") from None
            if not isinstance(data, dict):
                raise ClefError("invalid_state")
            yield data
            handle.seek(0)
            handle.write(json.dumps(data, allow_nan=False))
            handle.truncate()
            handle.flush()

    def reserve(self, session: str, policy: dict) -> bool:
        # All purposes share a budget. Failed calls count too, preventing retry storms.
        day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        with self.counters("daily-budget") as daily:
            count = daily.get("calls", 0) if daily.get("day") == day else 0
            if count >= policy["max_daily_calls"]:
                return False
            with self.counters(session) as data:
                calls = data.get("calls", 0)
                limit = policy["max_session_calls"]
                if limit is not None and calls >= limit:
                    return False
                data["calls"] = calls + 1
                daily.update(day=day, calls=count + 1)
        return True

    def records(self) -> list[dict]:
        try:
            raw = private_read(self.root / "decisions.jsonl", 10_010_000)
        except FileNotFoundError:
            return []
        try:
            return [json.loads(line) for line in raw.splitlines() if line.strip()]
        except ValueError:
            raise ClefError("invalid_log") from None
