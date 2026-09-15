"""Loopback-only, nonstreaming Ollama text subset for a bounded Codex experiment."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import threading
import time
import uuid

from codex_runner import DEFAULT_MODEL, GenerationError, generate

ALIAS = "bannerlord-codex"
MAX_BODY = 512 * 1024
MAX_TEXT = 120000


class RequestError(Exception):
    def __init__(self, status: int, message: str):
        self.status = status
        super().__init__(message)


def normalize(path: str, data: dict) -> tuple[list[dict], dict]:
    if not isinstance(data, dict):
        raise RequestError(400, "Expected a JSON object")
    if data.get("model") != ALIAS:
        raise RequestError(404, "Use model " + ALIAS)
    if data.get("stream") is not False:
        raise RequestError(400, "This prototype requires stream=false")
    allowed = {"model", "stream", "options", "keep_alive", "format"}
    allowed |= {"messages"} if path == "/api/chat" else {"system", "prompt"}
    if set(data) - allowed:
        raise RequestError(400, "Unsupported request fields: " + ", ".join(sorted(set(data) - allowed)))
    if data.get("format") not in (None, "", "json"):
        raise RequestError(400, "Only plain text or format=json is supported")
    options = data.get("options", {})
    supported = {"temperature", "top_p", "num_predict", "num_ctx", "repeat_penalty", "seed"}
    if not isinstance(options, dict) or set(options) - supported:
        raise RequestError(400, "Unsupported Ollama options")
    for value in options.values():
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise RequestError(400, "Invalid Ollama option value")
    if path == "/api/chat":
        messages = data.get("messages")
        if not isinstance(messages, list) or not 1 <= len(messages) <= 128:
            raise RequestError(400, "Expected 1 to 128 text messages")
    else:
        messages = []
        if data.get("system"):
            messages.append({"role": "system", "content": data["system"]})
        messages.append({"role": "user", "content": data.get("prompt")})
    for message in messages:
        if not isinstance(message, dict) or set(message) != {"role", "content"}:
            raise RequestError(400, "Only role and content are supported; no images or tools")
        if message["role"] not in {"system", "user", "assistant"} or not isinstance(message["content"], str):
            raise RequestError(400, "Invalid message role/content")
    if not any(m["content"].strip() for m in messages):
        raise RequestError(400, "Empty prompt")
    if sum(len(m["content"]) for m in messages) > MAX_TEXT:
        raise RequestError(413, "Prompt exceeds the prototype character limit")
    return messages, options


class Engine:
    def __init__(self, *, model=DEFAULT_MODEL, timeout=85, metrics=None, generator=generate):
        self.model, self.timeout, self.metrics, self.generator = model, timeout, metrics, generator
        self.lock = threading.Lock()
        self.cooldown_until = 0.0
        self.last_error = None

    def record(self, row):
        # Metadata only: never prompts, generated dialogue, CLI output, or credentials.
        if self.metrics:
            with self.metrics.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps(row, ensure_ascii=False) + "\n")

    def run(self, messages, *, require_json=False, ignored_options=None):
        if not self.lock.acquire(blocking=False):
            raise RequestError(429, "Another request is running; no generation was started")
        request_id = uuid.uuid4().hex
        started = time.monotonic()
        row = {"id": request_id, "time": datetime.now(timezone.utc).isoformat(), "model": self.model,
               "characters": sum(len(m["content"]) for m in messages),
               "ignored_ollama_options": sorted(ignored_options or {})}
        try:
            if time.monotonic() < self.cooldown_until:
                row.update(status="cooldown", error=self.last_error, generated=False)
                raise RequestError(503, "Previous Codex request failed (%s); retry cooldown prevents duplicate generation" % self.last_error)
            try:
                result = self.generator(messages, model=self.model, timeout=self.timeout)
                if require_json:
                    try:
                        json.loads(result["response"])
                    except (ValueError, TypeError):
                        raise GenerationError("schema", "Requested JSON was not valid; no retry was made")
            except GenerationError as error:
                self.last_error = error.kind
                self.cooldown_until = time.monotonic() + (60 if error.kind == "quota" else 30)
                row.update(status="error", error=error.kind, generated=True)
                status = 429 if error.kind == "quota" else 504 if error.kind == "timeout" else 502
                raise RequestError(status, str(error)) from error
            row.update(status="ok", generated=True, usage=result["usage"], seconds=result["seconds"], warnings=result.get("warnings", []))
            return result
        finally:
            row["wall_seconds"] = round(time.monotonic() - started, 3)
            try:
                self.record(row)
            finally:
                self.lock.release()


class Handler(BaseHTTPRequestHandler):
    server_version = "BannerlordCodexPrototype/0.1"

    def setup(self):
        super().setup()
        self.connection.settimeout(6)

    def log_message(self, *args):
        pass

    def reply(self, status, data):
        body = json.dumps(data, ensure_ascii=False, allow_nan=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        if status in (429, 503, 504):
            self.send_header("Retry-After", "60")
        self.end_headers()
        self.wfile.write(body)

    def check_peer(self):
        port = self.server.server_address[1]
        if self.client_address[0] != "127.0.0.1":
            raise RequestError(403, "Loopback only")
        if self.headers.get("Host", "") not in {"127.0.0.1:%d" % port, "localhost:%d" % port}:
            raise RequestError(403, "Invalid local Host header")
        if "Origin" in self.headers or "Sec-Fetch-Site" in self.headers:
            raise RequestError(403, "Browser requests are not supported")

    def do_GET(self):
        try:
            self.check_peer()
            if self.path == "/api/version":
                self.reply(200, {"version": "0.0.0-codex-prototype", "adapter": "Codex CLI text adapter"})
            elif self.path == "/api/tags":
                self.reply(200, {"models": [{"name": ALIAS, "model": ALIAS}]})
            elif self.path == "/healthz":
                self.reply(200, {"adapter_ready": True, "model": self.server.engine.model,
                                 "account_and_quota_verified": False})
            else:
                raise RequestError(404, "Unsupported endpoint")
        except RequestError as error:
            self.reply(error.status, {"error": str(error)})

    def do_POST(self):
        try:
            self.check_peer()
            if self.path not in ("/api/chat", "/api/generate"):
                raise RequestError(404, "Unsupported endpoint; text chat/generate only")
            if "Transfer-Encoding" in self.headers:
                raise RequestError(400, "Chunked requests are not supported")
            if self.headers.get_content_type() != "application/json":
                raise RequestError(415, "Expected application/json")
            try:
                length = int(self.headers.get("Content-Length", ""))
            except ValueError:
                raise RequestError(411, "Content-Length required")
            if not 0 < length <= MAX_BODY:
                raise RequestError(413, "Request body exceeds the prototype limit")
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise RequestError(400, "Incomplete request body")
            try:
                data = json.loads(raw)
            except (ValueError, UnicodeDecodeError):
                raise RequestError(400, "Invalid JSON body")
            messages, options = normalize(self.path, data)
            result = self.server.engine.run(messages, require_json=data.get("format") == "json", ignored_options=options)
            envelope = {"model": ALIAS, "created_at": datetime.now(timezone.utc).isoformat(), "done": True,
                        "done_reason": "stop", "total_duration": int(result["seconds"] * 1e9),
                        "prompt_eval_count": result["usage"].get("input_tokens", 0),
                        "eval_count": result["usage"].get("output_tokens", 0)}
            if self.path == "/api/chat":
                envelope["message"] = {"role": "assistant", "content": result["response"]}
            else:
                envelope["response"] = result["response"]
            self.reply(200, envelope)
        except RequestError as error:
            self.reply(error.status, {"error": str(error)})
        except (BrokenPipeError, ConnectionResetError):
            pass
        except TimeoutError:
            self.reply(408, {"error": "Request body timeout"})
        except Exception:
            # Do not leak implementation exceptions, local paths, or account details.
            self.reply(500, {"error": "Adapter failed internally; inspect local diagnostics"})


def serve(port=11435, **options):
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.daemon_threads = True
    server.engine = Engine(**options)
    return server


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=11435)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--timeout", type=float, default=85)
    parser.add_argument("--metrics", type=Path)
    args = parser.parse_args()
    if not 1 <= args.timeout <= 90:
        parser.error("timeout must be between 1 and 90 seconds")
    os.umask(0o077)
    server = serve(args.port, model=args.model, timeout=args.timeout, metrics=args.metrics)
    print("Experimental text adapter listening on 127.0.0.1:%d using %s" % (args.port, args.model), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
