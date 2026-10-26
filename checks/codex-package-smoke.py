"""Exercise account bootstrap and the managed-daemon package without user state."""

import hashlib
import json
import os
import select
import signal
import struct
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time


def check_voice_devices(package, env, require_defaults=False):
    """Exercise the copied helper without runtime, transport, or audio streams."""
    env = {key: value for key, value in env.items() if key in {
        "HOME", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "PULSE_SERVER",
        "PULSE_COOKIE", "PIPEWIRE_REMOTE", "TMPDIR",
    }}
    voice = package / "codex-resources/voice"
    manifest = json.loads((voice / "manifest.json").read_text())
    for name in ("codex-voice-host", "codex-voice-host.real"):
        binary = voice / "bin" / name
        assert binary.is_file() and os.access(binary, os.X_OK), binary
        digest = hashlib.sha256(binary.read_bytes()).hexdigest()
        assert manifest["sha256"][f"codex-resources/voice/bin/{name}"] == digest, name
    assert (voice / "bin/codex-voice-host.real").read_bytes().startswith(b"\x7fELF")
    process = subprocess.Popen(
        [str(voice / "bin/codex-voice-host")], env=env,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    errors = bytearray()

    def drain():
        while chunk := process.stderr.read(4096):
            errors.extend(chunk[:max(0, 16384 - len(errors))])

    reader = threading.Thread(target=drain, daemon=True)
    reader.start()

    def exact(size):
        result = bytearray()
        deadline = time.monotonic() + 10
        while len(result) < size:
            remaining = deadline - time.monotonic()
            assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], "voice reply timed out"
            chunk = os.read(process.stdout.fileno(), size - len(result))
            assert chunk, "voice helper output closed"
            result.extend(chunk)
        return bytes(result)

    def exchange(message):
        data = json.dumps(message).encode()
        process.stdin.write(struct.pack(">I", len(data)) + data)
        process.stdin.flush()
        length = struct.unpack(">I", exact(4))[0]
        assert length <= 128 * 1024, length
        return json.loads(exact(length))

    try:
        assert exchange({"type": "hello", "protocol": 1, "buildCommit": manifest["buildCommit"]}) == {"type": "ready"}
        for kind in ("input", "output"):
            response = exchange({"type": "listDevices", "kind": kind})
            assert response["type"] == "deviceList", response
            assert isinstance(response["devices"], list), response
            if require_defaults:
                assert any(device["isDefault"] for device in response["devices"]), (kind, response)
        assert exchange({"type": "close"}) == {"type": "closed"}
        assert process.wait(timeout=5) == 0
    finally:
        process.stdin.close()
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        reader.join(timeout=2)
        process.stdout.close()
        process.stderr.close()
    diagnostics = errors.decode(errors="replace")
    # Headless CI has no PipeWire server or hardware. Missing ALSA resources and
    # NixOS's incompatible multilib syntax still indicate a packaging regression.
    assert "Cannot access file" not in diagnostics, diagnostics
    assert "Unknown field libs" not in diagnostics, diagnostics
    print("Codex copied voice helper enumerated devices without opening streams")


def check_account_read(codex, root, env, check_config=False):
    # A daemon version query alone does not exercise the TUI's account bootstrap.
    # The fixture has no credentials: this checks protocol compatibility, not
    # live ChatGPT workspace routing or account-service availability.
    process = subprocess.Popen(
        [codex, "app-server", "--listen", "stdio://"],
        env=env,
        cwd=root,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    buffer = b""

    def send(message):
        process.stdin.write(json.dumps(message).encode() + b"\n")
        process.stdin.flush()

    def response(request_id):
        nonlocal buffer
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                message = json.loads(line)
                if message.get("id") == request_id:
                    assert "error" not in message, message
                    return message["result"]
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]:
                break
            chunk = os.read(process.stdout.fileno(), 65536)
            assert chunk, f"app-server exited before response {request_id}"
            buffer += chunk
        raise AssertionError(f"app-server response {request_id} timed out")

    try:
        send({"id": 1, "method": "initialize", "params": {
            "clientInfo": {"name": "system_manifest_smoke", "version": "1.0"}
        }})
        response(1)
        send({"method": "initialized", "params": {}})
        send({"id": 2, "method": "account/read", "params": {"refreshToken": False}})
        account = response(2)
        assert account["account"] is None, account
        assert account["requiresOpenaiAuth"] is True, account
        assert account.get("workspaceRouting") is None, account
        if check_config:
            send({"id": 3, "method": "config/read", "params": {"includeLayers": False}})
            config = response(3)["config"]
            assert config["model"] == "gpt-6.1-sol", config
            assert config["model_reasoning_effort"] == "medium", config
            assert config["plan_mode_reasoning_effort"] == "xhigh", config
            assert config["agents"]["default_subagent_model"] == "gpt-6.1-sol", config["agents"]
            assert config["agents"]["default_subagent_reasoning_effort"] == "medium", config["agents"]
            assert config["features"]["realtime_conversation"] is True, config["features"]
            assert config["realtime"]["voice"] == "vale", config["realtime"]
        print("Codex account/read bootstrap verified without credentials")
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        process.stdout.close()


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
    codex, expected_version, *config_source = sys.argv[1:]
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

        if config_source:
            (root / "codex/config.toml").write_bytes(Path(config_source[0]).read_bytes())

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
            check_account_read(codex, root, env, bool(config_source))
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
            require_audio = os.environ.get("SYSTEM_MANIFEST_REQUIRE_VOICE_DEFAULTS") == "1"
            voice_env = dict(env)
            if require_audio:
                # Only enumeration uses the real desktop audio socket. The
                # daemon and all persistent state stay in the private fixture.
                voice_env["XDG_RUNTIME_DIR"] = os.environ["XDG_RUNTIME_DIR"]
            check_voice_devices(package, voice_env, require_defaults=require_audio)
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
