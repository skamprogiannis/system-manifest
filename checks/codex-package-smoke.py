"""Exercise the installed CLI's managed-daemon package copy without user state."""

import json
import os
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def wait_for_managed_processes_to_exit(root):
    # The PID backend leaves its separate update loop running after daemon stop.
    # Stop only fixture-owned updaters before removing their copied package.
    deadline = time.monotonic() + 10
    while True:
        running = []
        for process in Path("/proc").iterdir():
            if not process.name.isdigit():
                continue
            try:
                executable = Path(os.readlink(process / "exe"))
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                continue
            if executable.is_relative_to(root):
                running.append(process.name)
                try:
                    arguments = (process / "cmdline").read_bytes().split(b"\0")
                    if arguments[1:5] == [b"app-server", b"daemon", b"pid-update-loop", b""]:
                        os.kill(int(process.name), signal.SIGTERM)
                except (FileNotFoundError, ProcessLookupError):
                    continue
        if not running:
            return
        if time.monotonic() >= deadline:
            raise AssertionError(f"Fixture daemon processes did not exit after stop: {running}")
        time.sleep(0.05)


def main():
    codex, expected_version = sys.argv[1:]
    # Keep Unix socket paths short, including inside a Nix build sandbox.
    with tempfile.TemporaryDirectory(prefix="cdx-", dir="/tmp") as temporary:
        root = Path(temporary)
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("CODEX_", "DIRENV_", "OPENAI_"))
        }
        for key, directory in {
            "HOME": "home",
            "CODEX_HOME": "codex",
            "XDG_CONFIG_HOME": "config",
            "XDG_CACHE_HOME": "cache",
            "XDG_DATA_HOME": "data",
            "XDG_STATE_HOME": "state",
            "XDG_RUNTIME_DIR": "run",
        }.items():
            path = root / directory
            path.mkdir(mode=0o700)
            env[key] = str(path)

        def run(*arguments):
            result = subprocess.run(
                [codex, *arguments],
                env=env,
                cwd=root,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode:
                raise AssertionError(
                    f"codex {' '.join(arguments)} exited {result.returncode}:\n"
                    f"{result.stdout}{result.stderr}"
                )
            return result.stdout.strip()

        try:
            assert run("--version") == f"codex-cli {expected_version}"
            run("app-server", "daemon", "start")
            package = root / "codex/packages/app-server-daemon/current"
            manifest = json.loads((package / "codex-package.json").read_text())
            assert manifest["version"] == expected_version, manifest
            assert manifest["entrypoint"] == "bin/codex", manifest
            for relative in (
                "bin/codex",
                "bin/codex-code-mode-host",
                "codex-path/rg",
                "codex-resources/bwrap",
            ):
                path = package / relative
                assert path.is_file() and os.access(path, os.X_OK), path
            # A successful query proves the copied executable is serving requests.
            version = json.loads(run("app-server", "daemon", "version"))
            assert version["status"] == "running", version
            for key in ("cliVersion", "managedCodexVersion", "appServerVersion"):
                assert version[key] == expected_version, version
            assert Path(version["managedCodexPath"]) == package / "bin/codex", version
            assert Path(version["socketPath"]).is_relative_to(root / "codex"), version
            print(f"Codex managed package and daemon verified: {version}")
        except BaseException:
            try:
                run("app-server", "daemon", "stop")
                wait_for_managed_processes_to_exit(root)
            except Exception as cleanup_error:
                print(f"Daemon cleanup also failed: {cleanup_error}", file=sys.stderr)
            raise
        else:
            run("app-server", "daemon", "stop")
            wait_for_managed_processes_to_exit(root)


if __name__ == "__main__":
    main()
