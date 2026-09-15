"""Experimental subscription-backed text runner. No game settings are changed."""
from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent
DEFAULT_MODEL = "gpt-5.6-sol"
# CLI 0.154.0 emits this even with code_mode=false. The host is intentionally
# unavailable; retain the diagnostic, accept it only before generation starts.
DISABLED_CODE_HOST_NOTICE = "Code Mode is unavailable because code-mode host is disabled. Code mode will fail closed; enable `features.code_mode_host` and install `codex-code-mode-host`."


class GenerationError(Exception):
    def __init__(self, kind: str, message: str):
        self.kind = kind
        super().__init__(message)


def command(model: str, workdir: str, executable: str = "codex") -> list[str]:
    settings = {
        "model_reasoning_effort": '"low"',
        "model_verbosity": '"low"',
        "personality": '"none"',
        "approval_policy": '"never"',
        "web_search": '"disabled"',
        "features.shell_tool": "false",
        "features.unified_exec": "false",
        "features.multi_agent": "false",
        "features.goals": "false",
        "features.apps": "false",
        "features.hooks": "false",
        "features.memories": "false",
        "features.remote_plugin": "false",
        "features.plugins": "false",
        "features.view_image": "false",
        "features.image_generation": "false",
        "features.browser_use": "false",
        "features.browser_use_external": "false",
        "features.computer_use": "false",
        "features.code_mode": "false",
        "features.code_mode_host": "false",
        "features.sleep_tool": "false",
        "features.skill_search": "false",
        "features.skip_host_skill_discovery": "true",
        "features.unbounded_connection_retries": "false",
        "features.shell_snapshot": "false",
        "features.skill_mcp_dependency_install": "false",
        "apps._default.enabled": "false",
        "project_doc_max_bytes": "0",
        "history.persistence": '"none"',
        "suppress_unstable_features_warning": "true",
        "model_instructions_file": json.dumps(str(ROOT / "model-instructions.txt")),
    }
    args = [executable, "exec", "--ignore-user-config", "--strict-config", "--ephemeral",
            "--skip-git-repo-check", "--sandbox", "read-only", "--cd", workdir,
            "--model", model, "--color", "never", "--json",
            "--output-schema", str(ROOT / "response.schema.json")]
    for key, value in settings.items():
        args += ["-c", key + "=" + value]
    return args + ["-"]


def environment() -> dict[str, str]:
    # Preserve OS/Nix paths and TLS configuration, never inherit a billing key or
    # coding-session control state. Codex reads its existing login itself.
    allowed = {"HOME", "PATH", "USER", "LOGNAME", "LANG", "LC_ALL", "TZ",
               "SSL_CERT_FILE", "SSL_CERT_DIR", "NIX_SSL_CERT_FILE", "LD_LIBRARY_PATH",
               "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME",
               "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
               "http_proxy", "https_proxy", "all_proxy", "no_proxy"}
    return {key: value for key, value in os.environ.items() if key in allowed}


def generate(messages: list[dict], *, model: str = DEFAULT_MODEL, timeout: float = 110,
             executable: str = "codex") -> dict:
    payload = json.dumps({"messages": messages}, ensure_ascii=False)
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="bannerlord-codex-request-") as workdir:
        # Refuse accidental API-key billing if the CLI's saved login changes.
        # Inspect the status locally; never log or return its raw output.
        try:
            login = subprocess.run([executable, "login", "status"], cwd=workdir, env=environment(),
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                   encoding="utf-8", timeout=min(15, timeout))
        except (OSError, subprocess.TimeoutExpired):
            raise GenerationError("auth", "Could not verify Codex ChatGPT sign-in; no generation started.")
        if login.returncode or not any(line.strip() == "Logged in using ChatGPT" for line in login.stdout.splitlines()):
            raise GenerationError("auth", "A saved ChatGPT login is required; API-key authentication is not accepted.")
        remaining = timeout - (time.monotonic() - started)
        if remaining <= 0:
            raise GenerationError("timeout", "Sign-in check exhausted the request deadline; no generation started.")
        proc = subprocess.Popen(command(model, workdir, executable), stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                encoding="utf-8", env=environment(), cwd=workdir, start_new_session=True)
        try:
            stdout, stderr = proc.communicate(payload, timeout=remaining)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.communicate()
            raise GenerationError("timeout", "Codex exceeded the request deadline; no retry was made.")
    elapsed = time.monotonic() - started
    events = []
    for line in stdout.splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            raise GenerationError("protocol", "Codex returned a non-JSON event.")
    if proc.returncode:
        # CLI errors may contain local paths; never return stderr or account data
        # to the game. Keep the failure classification explicit.
        combined = (stderr + stdout).lower()
        kind = "quota" if any(x in combined for x in ("usage limit", "rate limit", "quota")) else "codex_exit"
        error = GenerationError(kind, "Codex exited unsuccessfully (code %d); no retry was made." % proc.returncode)
        error.stderr = stderr
        error.events = events
        raise error
    permitted_items = {"agent_message", "reasoning"}
    warnings = []
    turn_started = False
    for event in events:
        if event.get("type") == "turn.started":
            turn_started = True
        item = event.get("item", {})
        if (not turn_started and event.get("type") == "item.completed"
                and item.get("type") == "error" and item.get("message") == DISABLED_CODE_HOST_NOTICE):
            warnings.append("coding_host_intentionally_disabled")
            continue
        if item and item.get("type") not in permitted_items:
            error = GenerationError("unexpected_item", "Unexpected Codex item type %r; result rejected." % item.get("type"))
            error.events = [{"type": e.get("type"), "item_type": e.get("item", {}).get("type"),
                             "item_keys": sorted(e.get("item", {})), "usage": e.get("usage"),
                             "startup_message": e.get("item", {}).get("message")
                             if e.get("item", {}).get("type") == "error" else None} for e in events]
            raise error
        if event.get("type") in {"turn.failed", "error"}:
            raise GenerationError("codex_failure", "Codex reported a failed request.")
    final = [e["item"]["text"] for e in events if e.get("type") == "item.completed"
             and e.get("item", {}).get("type") == "agent_message"]
    completed = [e for e in events if e.get("type") == "turn.completed"]
    if len(final) != 1 or len(completed) != 1:
        raise GenerationError("protocol", "Expected one final text response and one completed turn.")
    try:
        value = json.loads(final[0])
        if set(value) != {"response"} or not isinstance(value["response"], str) or not value["response"].strip():
            raise ValueError()
    except (ValueError, TypeError):
        raise GenerationError("schema", "Codex did not return the required text response envelope.")
    return {"response": value["response"], "model": model, "seconds": round(elapsed, 3),
            "usage": completed[0].get("usage", {}), "warnings": warnings,
            "event_types": sorted({e.get("type", "") for e in events})}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("request", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--timeout", type=float, default=110)
    args = parser.parse_args()
    os.umask(0o077)
    request = json.loads(args.request.read_text())
    try:
        result = generate(request["messages"], model=args.model, timeout=args.timeout)
    except GenerationError as error:
        result = {"error": error.kind, "message": str(error),
                  "diagnostic": getattr(error, "stderr", ""), "events": getattr(error, "events", [])}
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"error": error.kind, "message": str(error)}))
        raise SystemExit(1)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("model", "seconds", "usage", "event_types")}))
