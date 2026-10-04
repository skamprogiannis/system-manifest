"""Verify installed local launch isolation without credentials or model inference."""

import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import tempfile
import time


def main():
    codex, assisted = sys.argv[1:]
    with tempfile.TemporaryDirectory(prefix="clf-", dir="/tmp") as temporary:
        root = Path(temporary)
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("CODEX_", "DIRENV_", "OPENAI_", "CLOUDFLARE_"))
        }
        for key, directory in {
            "HOME": "home", "CODEX_HOME": "codex", "XDG_CONFIG_HOME": "config",
            "XDG_CACHE_HOME": "cache", "XDG_DATA_HOME": "data",
            "XDG_STATE_HOME": "state", "XDG_RUNTIME_DIR": "run",
        }.items():
            path = root / directory
            path.mkdir(mode=0o700)
            env[key] = str(path)
        env["TERM"] = "xterm-256color"

        for arguments in (
            ["--help"],
            ["status"],
            ["status", "--json"],
            ["clef", "--help"],
        ):
            result = subprocess.run(
                [assisted, *arguments],
                env=env,
                cwd=root,
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, result.stderr
            assert "entry.py" not in result.stdout, (
                "frontend exposes internal entrypoint"
            )
            if arguments == ["status", "--json"]:
                assert json.loads(result.stdout)["usage_today"]["successful_calls"] == 0
        assert not (root / "state/codex-clef").exists(), (
            "diagnostics created decision state"
        )

        def daemon(command):
            socket = root / "codex/app-server-control/app-server-control.sock"
            if command == "version" and not socket.exists():
                return {"status": "not_running"}
            result = subprocess.run(
                [codex, "app-server", "daemon", command], env=env, cwd=root,
                capture_output=True, text=True, timeout=15,
            )
            assert result.returncode == 0, result.stderr
            return json.loads(result.stdout) if command == "version" else None

        def launch(mode):
            master, slave = pty.openpty()
            process = subprocess.Popen(
                [assisted, "--mode", mode, "--"], env=env, cwd=root,
                stdin=slave, stdout=slave, stderr=slave, start_new_session=True,
            )
            os.close(slave)
            output = bytearray()
            native_arguments = None
            try:
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline and process.poll() is None:
                    try:
                        arguments = Path(f"/proc/{process.pid}/cmdline").read_bytes().split(b"\0")
                    except FileNotFoundError:
                        break
                    if arguments and Path(os.fsdecode(arguments[0])).name == "codex":
                        native_arguments = arguments
                    if select.select([master], [], [], 0.1)[0]:
                        try:
                            output.extend(os.read(master, 65536))
                        except OSError:
                            break
                    if native_arguments is not None and b"\x1b[6n" in output:
                        break
                assert native_arguments is not None, "launcher did not reach native Codex"
                assert b"--no-daemon" in native_arguments, "assisted launch attached to shared daemon"
                assert b"unexpected argument" not in output, "native CLI rejected launcher arguments"
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                os.close(master)

        try:
            # Assisted startup first must leave no enabled environment in a daemon.
            for mode in ("shadow", "apply"):
                launch(mode)
                assert daemon("version")["status"] != "running", "assisted launch started shared daemon"
            # A plain daemon started first must not absorb assisted invocations.
            daemon("start")
            for mode in ("shadow", "apply"):
                launch(mode)
                assert daemon("version")["status"] == "running"
            print("Installed assisted launcher isolated in both modes and startup orders")
        finally:
            daemon("stop")


if __name__ == "__main__":
    main()
