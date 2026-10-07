"""Recover only the pinned CLI's fatal pre-session account-routing timeout."""

import os
import re
import select
import signal
import subprocess
import sys
import time


BOOTSTRAP_TIMEOUT = (
    "Error: account/read failed during TUI bootstrap: account/read failed: "
    "workspace routing discovery timed out (code -32603)"
)
_ANSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")


def _routing_timeout(status: int, stderr: bytes) -> bool:
    lines = _ANSI.sub(b"", stderr).decode("utf-8", errors="replace").splitlines()
    return status == 1 and bool(lines) and lines[-1].strip() == BOOTSTRAP_TIMEOUT


def launch_interactive(
    binary: str, arguments: list[str], env: dict, *, backoff=1
) -> int:
    # Native TUI input/rendering retain the caller's terminal and foreground group.
    # Only stderr is relayed; retain a bounded tail in memory, never a transcript.
    child = None
    interrupted = None

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
                arguments, executable=binary, env=env, stderr=subprocess.PIPE
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
            if interrupted or attempt == 2 or not _routing_timeout(status, bytes(tail)):
                return status if status >= 0 else 128 - status
            print(
                f"Codex account routing timed out; retrying startup ({attempt + 1}/2).",
                file=sys.stderr,
            )
            time.sleep(backoff)
        raise AssertionError("unreachable")
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
