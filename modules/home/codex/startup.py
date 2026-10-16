"""Recover only the pinned CLI's fatal pre-session account-routing timeout."""

from dataclasses import dataclass
import os
from pathlib import Path
import re
import select
import signal
import socket
import struct
import subprocess
import sys
import time


_NATIVE_COMMANDS = {
    "agents",
    "exec",
    "e",
    "review",
    "login",
    "logout",
    "mcp",
    "plugin",
    "app-server",
    "remote-control",
    "app",
    "completion",
    "update",
    "doctor",
    "sandbox",
    "debug",
    "execpolicy",
    "apply",
    "a",
    "resume",
    "queue",
    "archive",
    "delete",
    "migrate-rollouts",
    "unarchive",
    "fork",
    "cloud",
    "cloud-tasks",
    "responses-api-proxy",
    "stdio-to-uds",
    "exec-server",
    "features",
    "help",
    "tcp-tunnel",
}
_NATIVE_VALUES = {
    "--config",
    "--model",
    "--profile",
    "--cd",
    "--image",
    "--sandbox",
    "--ask-for-approval",
    "--enable",
    "--disable",
    "--remote",
    "--remote-auth-token-env",
    "--local-provider",
    "--add-dir",
}
_NATIVE_SHORT_VALUES = {
    "-c": "--config",
    "-m": "--model",
    "-p": "--profile",
    "-C": "--cd",
    "-i": "--image",
    "-s": "--sandbox",
    "-a": "--ask-for-approval",
}


@dataclass(frozen=True)
class LaunchContext:
    interactive: bool
    no_daemon: bool


def launch_context(arguments: list[str]) -> LaunchContext:
    """Classify native entrypoints only; preserve every user argument verbatim."""
    no_daemon = False
    positional = False
    index = 0
    while index < len(arguments):
        token = arguments[index]
        index += 1
        if token == "--":
            break
        if token in {"-h", "--help", "-V", "--version"}:
            return LaunchContext(False, False)
        if token == "--no-daemon":
            no_daemon = True
            continue
        option, separator, _ = token.partition("=")
        if token.startswith("-") and not token.startswith("--"):
            option = _NATIVE_SHORT_VALUES.get(token[:2], token)
            separator = bool(token[2:])
        if option == "--remote":
            return LaunchContext(False, False)
        if option in _NATIVE_VALUES:
            if not separator:
                index += 1
                if option == "--image":
                    while index < len(arguments) and not arguments[index].startswith("-"):
                        index += 1
            continue
        if token.startswith("-"):
            continue
        if not positional and token in _NATIVE_COMMANDS:
            if token not in {"resume", "fork"}:
                return LaunchContext(False, False)
        positional = True
    return LaunchContext(True, no_daemon)


BOOTSTRAP_TIMEOUT = (
    "Error: account/read failed during TUI bootstrap: account/read failed: "
    "workspace routing discovery timed out (code -32603)"
)
_ANSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")


def _routing_timeout(status: int, stderr: bytes) -> bool:
    lines = _ANSI.sub(b"", stderr).decode("utf-8", errors="replace").splitlines()
    return status == 1 and bool(lines) and lines[-1].strip() == BOOTSTRAP_TIMEOUT


def _ordinary_daemon_safe(env: dict) -> bool:
    """Do not reuse a server whose captured environment enables assisted hooks."""
    if any(env.get(key) == "1" for key in ("CODEX_AUTO_ENABLED", "CODEX_CLEF_ENABLED")):
        return False
    home = Path(
        env.get("CODEX_HOME") or Path(env.get("HOME") or Path.home()) / ".codex"
    )
    endpoint = home / "app-server-control/app-server-control.sock"
    try:
        try:
            endpoint.stat()
        except FileNotFoundError:
            return True
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
            peer.settimeout(0.2)
            try:
                peer.connect(str(endpoint))
            except (FileNotFoundError, ConnectionRefusedError):
                # Native startup can create a daemon from the disabled client environment.
                return True
            pid, uid, _ = struct.unpack(
                "3i", peer.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
            )
            if pid <= 0 or uid != os.getuid():
                return False
            with Path(f"/proc/{pid}/environ").open("rb") as handle:
                snapshot = handle.read(1_048_577)
            if len(snapshot) > 1_048_576:
                return False
            return not {b"CODEX_AUTO_ENABLED=1", b"CODEX_CLEF_ENABLED=1"}.intersection(snapshot.split(b"\0"))
    except (OSError, ValueError, struct.error):
        return False


def launch_interactive(
    binary: str, arguments: list[str], env: dict, *, backoff=1, fallback=None
) -> int:
    # Native TUI input/rendering retain the caller's terminal and foreground group.
    # Only stderr is relayed; retain a bounded tail in memory, never a transcript.
    child = None
    interrupted = None
    ordinary = False

    def interrupt(signum, _frame):
        nonlocal interrupted
        interrupted = signum
        if child is not None and child.poll() is None:
            try:
                child.send_signal(signum)
            except ProcessLookupError:
                pass

    previous = {
        sig: signal.signal(sig, interrupt)
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
    }
    try:
        for attempt in range(3):
            if interrupted:
                return 128 + interrupted
            tail = bytearray()
            child = subprocess.Popen(
                arguments, executable=binary, env=dict(env, CODEX_STARTUP_SUPERVISED="1"), stderr=subprocess.PIPE
            )
            try:
                # Python can deliver a signal before Popen returns and assigns child.
                if interrupted:
                    try:
                        child.send_signal(interrupted)
                    except ProcessLookupError:
                        pass
                pipe = child.stderr
                os.set_blocking(pipe.fileno(), False)
                exited_at = None
                while True:
                    if child.poll() is not None:
                        if exited_at is None:
                            exited_at = time.monotonic()
                        # Descendants can retain fd2 after the native process exits.
                        if time.monotonic() - exited_at >= 0.2:
                            break
                    if not select.select([pipe], [], [], 0.05)[0]:
                        continue
                    try:
                        chunk = os.read(pipe.fileno(), 4096)
                    except BlockingIOError:
                        continue
                    if not chunk:
                        break
                    sys.stderr.buffer.write(chunk)
                    sys.stderr.buffer.flush()
                    tail.extend(chunk)
                    del tail[:-65536]
                status = child.wait()
            except BaseException:
                # Relay/setup failures must not leave an interactive native process behind.
                if child.poll() is None:
                    try:
                        child.terminate()
                    except ProcessLookupError:
                        pass
                try:
                    child.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
                raise
            finally:
                child.stderr.close()
            if interrupted or ordinary or not _routing_timeout(status, bytes(tail)):
                return status if status >= 0 else 128 - status
            if fallback is not None:
                fallback_arguments, fallback_env = fallback
                fallback = None
                if _ordinary_daemon_safe(fallback_env):
                    print(
                        "Assisted startup timed out; trying ordinary Codex without delegation hooks.",
                        file=sys.stderr,
                    )
                    arguments, env = fallback_arguments, fallback_env
                    ordinary = True
                    continue
                print(
                    "Ordinary Codex fallback skipped: daemon hook state is enabled or could not be verified.",
                    file=sys.stderr,
                )
            if attempt == 2:
                return status
            print(
                f"Codex account routing timed out; retrying startup ({attempt + 1}/2).",
                file=sys.stderr,
            )
            time.sleep(backoff)
        raise AssertionError("unreachable")
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
