"""Experimental subscription-backed text runner. No game settings are changed."""
from __future__ import annotations

import json
import os
import re
from pathlib import Path
import signal
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent
DEFAULT_MODEL = "gpt-5.6-sol"
# The CLI emits this even with code_mode=false. The host is intentionally
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


KNOWN_EVENTS = {"thread.started", "turn.started", "turn.completed", "turn.failed", "error",
                "item.started", "item.updated", "item.completed"}
KNOWN_ITEMS = {"agent_message", "reasoning", "error", "command_execution", "tool_call"}
USAGE_FIELDS = {"input_tokens", "cached_input_tokens", "cache_write_input_tokens",
                "output_tokens", "reasoning_output_tokens"}
RETRY_NOTICE = re.compile(r"^Reconnecting\.\.\.\s+\d+/\d+\b", re.IGNORECASE)


def error_category(message: str, *, fallback="codex_failure") -> str:
    """Classify local error text, returning only a fixed vocabulary."""
    text = message.lower() if isinstance(message, str) else ""
    if any(word in text for word in ("unauthorized", "authentication", "refresh token", "token expired",
                                    "login expired", "sign in", "not logged in")) or re.search(r"\b(?:401|403)\b", text):
        return "auth"
    if any(word in text for word in ("usage limit", "rate limit", "quota exceeded", "quota exhausted")) or re.search(r"\b429\b", text):
        return "quota"
    if any(word in text for word in ("model is not supported", "model not supported", "model is unavailable",
                                    "model not found", "do not have access to model", "unsupported model")):
        return "model_unavailable"
    if any(word in text for word in ("context window", "context length", "maximum context")):
        return "context"
    if any(word in text for word in ("stream disconnected", "stream closed", "connection reset",
                                    "connection refused", "failed to connect", "error sending request",
                                    "network error", "request timed out", "reconnecting...")):
        return "transport"
    if any(word in text for word in ("service unavailable", "server overloaded", "internal server error",
                                    "bad gateway", "gateway timeout")) or re.search(r"http(?: status(?: code)?)?\s+5\d\d\b", text):
        return "upstream"
    return fallback


def event_error_message(event: dict) -> str | None:
    if event.get("type") == "error":
        return event.get("message", "")
    if event.get("type") == "turn.failed":
        error = event.get("error")
        return error.get("message", "") if isinstance(error, dict) else ""
    item = event.get("item")
    if isinstance(item, dict) and item.get("type") == "error":
        if item.get("message") != DISABLED_CODE_HOST_NOTICE:
            return item.get("message", "")
    return None


def generation_diagnostic(stdout: str, *, started: float, login_seconds: float,
                          phase="generation", ticks=None, exit_code=None, recovered=False) -> dict:
    """Bounded counters, categories and timings; no event payloads or identifiers."""
    counts, items, categories = {}, {}, {}
    invalid_lines, retry = 0, False
    for line in stdout.splitlines():
        try:
            event = json.loads(line)
            if not isinstance(event, dict):
                raise ValueError()
        except (ValueError, TypeError):
            invalid_lines += 1
            continue
        event_type = event.get("type")
        event_type = event_type if isinstance(event_type, str) and event_type in KNOWN_EVENTS else "other"
        counts[event_type] = counts.get(event_type, 0) + 1
        if event_type == "item.completed" and isinstance(event.get("item"), dict):
            item_type = event["item"].get("type")
            item_type = item_type if isinstance(item_type, str) and item_type in KNOWN_ITEMS else "other"
            items[item_type] = items.get(item_type, 0) + 1
        message = event_error_message(event)
        if message is not None:
            category = error_category(message)
            categories[category] = categories.get(category, 0) + 1
            retry = retry or bool(isinstance(message, str) and RETRY_NOTICE.match(message))
    elapsed = max(0, time.monotonic() - started)
    completion = (ticks or {}).get("turn.completed")
    generation_end = min(elapsed, max(login_seconds, completion - started)) if completion is not None else elapsed
    timings = {"auth_seconds": round(login_seconds, 3),
               "generation_seconds": round(max(0, generation_end - login_seconds), 3),
               "completion_seconds": round(max(0, elapsed - generation_end), 3)}
    return {"phase": phase, "login_seconds": round(login_seconds, 3),
            "elapsed_seconds": round(elapsed, 3), "timings": timings,
            "turn_started": bool(counts.get("turn.started")),
            "turn_completed": bool(counts.get("turn.completed")),
            "turn_failed": bool(counts.get("turn.failed")),
            "retry_observed": retry, "recovered_error": recovered,
            "event_counts": counts, "item_counts": items, "error_categories": categories,
            "invalid_event_lines": invalid_lines, "exit_code": exit_code}


class EventCapture:
    """Observe completion as stdout arrives while communicate drains stdin/stderr."""
    def __init__(self, stream):
        self.stream, self.lines, self.ticks = stream, [], {}
        self.read_failed = False
        self.thread = threading.Thread(target=self.read, daemon=True)
        self.thread.start()

    def read(self):
        try:
            for line in self.stream:
                self.lines.append(line)
                try:
                    event = json.loads(line)
                    if isinstance(event, dict) and event.get("type") in {"turn.started", "turn.completed", "turn.failed"}:
                        self.ticks.setdefault(event["type"], time.monotonic())
                except (ValueError, TypeError):
                    pass  # The caller rejects malformed output after collection.
        except (OSError, UnicodeError):
            self.read_failed = True
        finally:
            try:
                self.stream.close()
            except OSError:
                self.read_failed = True

    @property
    def stdout(self):
        return "".join(self.lines)


def generate(messages: list[dict], *, model: str = DEFAULT_MODEL, timeout: float = 110,
             executable: str = "codex") -> dict:
    payload = json.dumps({"messages": messages}, ensure_ascii=False)
    started = time.monotonic()
    login_seconds, stdout, stderr, ticks, exit_code = 0.0, "", "", {}, None

    def fail(kind, message, *, phase="generation"):
        error = GenerationError(kind, message)
        error.diagnostic = generation_diagnostic(stdout, started=started, login_seconds=login_seconds,
                                                 phase=phase, ticks=ticks, exit_code=exit_code)
        raise error

    with tempfile.TemporaryDirectory(prefix="bannerlord-codex-request-") as workdir:
        # Inspect the saved login locally; never retain account output.
        try:
            login = subprocess.run([executable, "login", "status"], cwd=workdir, env=environment(),
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                   encoding="utf-8", timeout=min(15, timeout))
        except subprocess.TimeoutExpired:
            login_seconds = time.monotonic() - started
            if login_seconds >= timeout:
                fail("timeout", "Sign-in check exhausted the request deadline; no generation started.", phase="auth")
            fail("auth", "Could not verify Codex ChatGPT sign-in; no generation started.", phase="auth")
        except OSError:
            login_seconds = time.monotonic() - started
            fail("auth", "Could not verify Codex ChatGPT sign-in; no generation started.", phase="auth")
        login_seconds = time.monotonic() - started
        if login.returncode or not any(line.strip() == "Logged in using ChatGPT" for line in login.stdout.splitlines()):
            fail("auth", "A saved ChatGPT login is required; API-key authentication is not accepted.", phase="auth")
        remaining = timeout - login_seconds
        if remaining <= 0:
            fail("timeout", "Sign-in check exhausted the request deadline; no generation started.", phase="auth")
        try:
            proc = subprocess.Popen(command(model, workdir, executable), stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                    encoding="utf-8", env=environment(), cwd=workdir, start_new_session=True)
        except OSError:
            fail("codex_exit", "Could not start Codex; no generation started.", phase="startup")
        capture = EventCapture(proc.stdout)
        # communicate retains its existing deadline-safe stdin/stderr handling.
        # The capture owns stdout so it can timestamp completion before shutdown.
        proc.stdout = None
        timed_out = False
        try:
            _stdout, stderr = proc.communicate(payload, timeout=max(0, timeout - (time.monotonic() - started)))
            capture.thread.join(timeout=max(0, timeout - (time.monotonic() - started)))
            timed_out = capture.thread.is_alive()
        except subprocess.TimeoutExpired:
            timed_out = True
        if timed_out:
            cleanup_deadline = time.monotonic() + 3
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                _stdout, stderr = proc.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                _stdout, stderr = proc.communicate()
            capture.thread.join(timeout=max(0, cleanup_deadline - time.monotonic()))
            if capture.thread.is_alive():
                # A descendant can retain stdout after the CLI exits. It must
                # receive the same forced shutdown as a stalled CLI process.
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                capture.thread.join(timeout=1)
        stdout, ticks, exit_code = capture.stdout, capture.ticks, proc.returncode
        if timed_out:
            fail("timeout", "Codex exceeded the request deadline; no retry was made.")
        if capture.read_failed:
            fail("protocol", "Could not read Codex JSON events.", phase="completion")

    events = []
    for line in stdout.splitlines():
        try:
            event = json.loads(line)
            if not isinstance(event, dict) or not isinstance(event.get("type"), str):
                raise ValueError()
            if "item" in event and (not isinstance(event["item"], dict)
                                    or not isinstance(event["item"].get("type"), str)):
                raise ValueError()
            events.append(event)
        except (ValueError, TypeError):
            fail("protocol", "Codex returned an invalid JSON event.", phase="completion")

    failed = [e for e in events if e["type"] == "turn.failed"]
    error_messages = [message for e in events if (message := event_error_message(e)) is not None]
    if proc.returncode or failed:
        # Use terminal cause first. Dialogue/reasoning text never participates in
        # classification, and no raw CLI errors escape into logs or the game.
        terminal = event_error_message(failed[-1]) if failed else stderr
        fallback = "codex_exit" if proc.returncode else "codex_failure"
        kind = error_category(terminal, fallback=fallback)
        if kind == fallback:
            for message in reversed(error_messages):
                kind = error_category(message, fallback=fallback)
                if kind != fallback:
                    break
        fail(kind, "Codex failed (%s); no retry was made." % kind)

    permitted_items, warnings, turn_started, completed_seen = {"agent_message", "reasoning"}, [], False, False
    recovered = False
    for event in events:
        if event["type"] == "turn.started":
            turn_started = True
        item = event.get("item", {})
        if (not turn_started and event["type"] == "item.completed"
                and item.get("type") == "error" and item.get("message") == DISABLED_CODE_HOST_NOTICE):
            warnings.append("coding_host_intentionally_disabled")
            continue
        if item and item.get("type") not in permitted_items:
            fail("unexpected_item", "Unexpected Codex item; result rejected.", phase="completion")
        if event["type"] == "error":
            # Codex exec 0.160 drops ErrorNotification.willRetry. Recovery is
            # established only by the later completed turn and successful exit.
            if completed_seen:
                fail(error_category(event.get("message")), "Codex reported an error after completion; result rejected.", phase="completion")
            recovered = True
        if event["type"] == "turn.completed":
            completed_seen = True

    final = [e["item"].get("text") for e in events if e["type"] == "item.completed"
             and e.get("item", {}).get("type") == "agent_message"]
    completed = [e for e in events if e["type"] == "turn.completed"]
    if len(final) != 1 or len(completed) != 1:
        fail("protocol", "Expected one final text response and one completed turn.", phase="completion")
    try:
        value = json.loads(final[0])
        if not isinstance(value, dict) or set(value) != {"response"} or not isinstance(value["response"], str) or not value["response"].strip():
            raise ValueError()
    except (ValueError, TypeError):
        fail("schema", "Codex did not return the required text response envelope.", phase="completion")
    if recovered:
        warnings.append("cli_error_recovered")
    diagnostic = generation_diagnostic(stdout, started=started, login_seconds=login_seconds,
                                       phase="complete", ticks=ticks, exit_code=exit_code, recovered=recovered)
    raw_usage = completed[0].get("usage")
    usage = {k: v for k, v in raw_usage.items() if k in USAGE_FIELDS and type(v) is int and v >= 0} if isinstance(raw_usage, dict) else {}
    return {"response": value["response"], "model": model, "seconds": diagnostic["elapsed_seconds"],
            "usage": usage, "warnings": warnings, "diagnostic": diagnostic,
            "event_types": sorted(diagnostic["event_counts"])}


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
                  "diagnostic": getattr(error, "diagnostic", {})}
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"error": error.kind, "message": str(error)}))
        raise SystemExit(1)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("model", "seconds", "usage", "event_types")}))
