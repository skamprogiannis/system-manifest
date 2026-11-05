"""Check native tmux detach/reattach with the generated Home Manager config."""

import os
from pathlib import Path
import pty
import signal
import subprocess
import sys
import tempfile
import time


tmux, config = sys.argv[1:]

with tempfile.TemporaryDirectory(prefix="tmux-smoke-") as directory:
    command = [tmux, "-S", str(Path(directory) / "socket"), "-f", config]
    environment = dict(os.environ, TERM="xterm-256color")
    environment.pop("TMUX", None)

    def run(*arguments, check=True):
        return subprocess.run(
            [*command, *arguments], env=environment, text=True,
            capture_output=True, check=check, timeout=5,
        )

    def attach_and_detach():
        pid, terminal = pty.fork()
        if pid == 0:
            os.execve(tmux, [*command, "attach-session", "-t", "persistent"], environment)

        reaped = False
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                clients = run("list-clients", "-F", "#{client_pid}").stdout.splitlines()
                if str(pid) in clients:
                    break
                time.sleep(0.05)
            else:
                raise AssertionError("Native tmux client failed to attach")

            # Standard Ctrl+B, then D must detach without ending the session.
            os.write(terminal, b"\x02d")
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                completed, status = os.waitpid(pid, os.WNOHANG)
                if completed:
                    reaped = True
                    assert os.waitstatus_to_exitcode(status) == 0, status
                    break
                time.sleep(0.05)
            else:
                raise AssertionError("Ctrl+B D failed to detach")
            run("has-session", "-t", "persistent")
        finally:
            os.close(terminal)
            if not reaped:
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                os.waitpid(pid, 0)

    try:
        run("new-session", "-d", "-s", "persistent", "sleep 60")
        for option, expected in [
            ("prefix", "C-b"),
            ("default-terminal", "tmux-256color"),
            ("bell-action", "any"),
        ]:
            assert run("show-options", "-gv", option).stdout.strip() == expected, option
        assert "xterm-ghostty:RGB" in run("show-options", "-s", "terminal-features").stdout
        attach_and_detach()
        attach_and_detach()
        print("tmux: managed config, terminal features, detach and reattach passed")
    finally:
        run("kill-server", check=False)
