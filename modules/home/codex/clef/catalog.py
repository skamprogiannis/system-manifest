"""Discover model/effort pairs through the native app-server, without inference."""

import json
import os
from pathlib import Path
import selectors
import re
import subprocess
import tempfile
import time

from .client import ClefError, private_read
from .state import Store, locked


def pairs(models: list, policy: dict) -> list[dict]:
    result = []
    for model in models:
        name = model.get("model")
        if name not in policy["models"] or model.get("hidden", False):
            continue
        for entry in model.get("supportedReasoningEfforts", []):
            effort = entry.get("reasoningEffort")
            if not isinstance(effort, str) or not re.fullmatch(
                r"[a-z][a-z0-9_]{0,31}", effort
            ):
                continue
            candidate = {
                "model": name,
                "effort": effort,
                "description": name
                + ": "
                + policy["models"][name]
                + "; reasoning effort: "
                + effort
                + "; "
                + str(entry.get("description", ""))[:300],
            }
            if candidate not in result:
                result.append(candidate)
    if not result:
        raise ClefError("no_available_models")
    return result


class RPC:
    """One bounded stdio connection; never creates a model turn."""

    def __init__(self, codex: str, timeout: float = 15):
        self.codex = codex
        self.timeout = timeout
        self.process = None
        self.buffer = b""
        self.sequence = 0

    def __enter__(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="clef-catalog-")
        env = dict(os.environ)
        env["CODEX_CLEF_ENABLED"] = "0"
        for key in ("CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"):
            env.pop(key, None)
        self.process = subprocess.Popen(
            [
                self.codex,
                "-c",
                "features.hooks=false",
                "app-server",
                "--listen",
                "stdio://",
            ],
            cwd=self.temporary.name,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        try:
            self.request(
                "initialize", {"clientInfo": {"name": "codex_clef", "version": "1.0"}}
            )
            self.send({"method": "initialized", "params": {}})
        except BaseException:
            self.__exit__(None, None, None)
            raise
        return self

    def send(self, message: dict):
        try:
            self.process.stdin.write(json.dumps(message).encode() + b"\n")
            self.process.stdin.flush()
        except (OSError, BrokenPipeError):
            raise ClefError("catalog_unavailable") from None

    def request(self, method: str, params: dict) -> dict:
        self.sequence += 1
        self.send({"id": self.sequence, "method": method, "params": params})
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                try:
                    message = json.loads(line)
                except ValueError:
                    raise ClefError("invalid_catalog_response") from None
                if message.get("id") != self.sequence:
                    continue
                if "error" in message or not isinstance(message.get("result"), dict):
                    raise ClefError("catalog_error")
                return message["result"]
            if not self.selector.select(max(0, deadline - time.monotonic())):
                break
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                raise ClefError("catalog_unavailable")
            self.buffer += chunk
            if len(self.buffer) > 1_000_000:
                raise ClefError("catalog_too_large")
        raise ClefError("catalog_timeout")

    def __exit__(self, *_):
        if self.process:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
            self.process.stdout.close()
            self.selector.close()
        self.temporary.cleanup()


def scope() -> str:
    home = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
    auth = home / "auth.json"
    try:
        stamp = str(auth.stat().st_mtime_ns)
    except FileNotFoundError:
        stamp = "none"
    from .state import session_key

    return session_key(str(home.absolute()) + ":" + stamp)


def refresh(codex: str, policy: dict, store: Store) -> list[dict]:
    models = []
    with RPC(codex) as rpc:
        cursor = None
        seen = set()
        for _ in range(20):
            page = rpc.request(
                "model/list", {"limit": 50, "includeHidden": False, "cursor": cursor}
            )
            if not isinstance(page.get("data"), list):
                raise ClefError("invalid_catalog_response")
            models.extend(page["data"])
            cursor = page.get("nextCursor")
            if cursor is None:
                break
            if not isinstance(cursor, str) or cursor in seen:
                raise ClefError("invalid_catalog_cursor")
            seen.add(cursor)
        else:
            raise ClefError("catalog_page_limit")
    available = pairs(models, policy)
    with locked(store.root / "catalog.json") as handle:
        handle.seek(0)
        json.dump(
            {
                "time": time.time(),
                "scope": scope(),
                "version": policy["codex_version"],
                "models": models,
            },
            handle,
        )
        handle.truncate()
    return available


def cached(policy: dict, store: Store) -> list[dict]:
    try:
        data = json.loads(private_read(store.root / "catalog.json", 1_000_000))
    except (OSError, ValueError):
        raise ClefError("missing_catalog") from None
    age = time.time() - data.get("time", 0)
    if (
        data.get("scope") != scope()
        or data.get("version") != policy["codex_version"]
        or not 0 <= age < policy["catalog_ttl_seconds"]
    ):
        raise ClefError("stale_catalog")
    return pairs(data["models"], policy)
