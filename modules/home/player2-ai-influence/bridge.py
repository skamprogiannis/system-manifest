#!/usr/bin/env python3
"""Local AI Influence transport to the official Player2 Web API.

This is not the Player2 desktop client. Desktop microphone capture and local
audio playback are unsupported and return explicit errors. Request/response
bodies are never logged or rewritten. No credentials are returned to clients.
"""
import argparse
import concurrent.futures
import http.server
import json
import os
import socket
import stat
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

CLIENT_ID = "0199bcdd-3f9f-7a67-947e-ca10021b94ce"
UPSTREAM = "https://api.player2.game"
MAX_BODY = 32 * 1024 * 1024
ROUTES = {
    "GET": {"/v1/health", "/v1/joules", "/v1/tts/voices"},
    "POST": {"/v1/chat/completions", "/v1/embeddings", "/v1/image/generate",
             "/v1/image/edit", "/v1/tts/speak"},
}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Bridge(http.server.HTTPServer):
    def __init__(self, address, key, upstream=UPSTREAM):
        self.key = key
        self.upstream = upstream
        self.opener = urllib.request.build_opener(NoRedirect)
        self.slots = threading.BoundedSemaphore(4)
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=4)
        super().__init__(address, Handler)

    def process_request(self, request, client_address):
        # No unbounded thread/queued-request growth while the game is busy.
        if not self.slots.acquire(blocking=False):
            try:
                request.sendall(b'HTTP/1.0 503 Service Unavailable\r\nRetry-After: 1\r\nContent-Length: 0\r\n\r\n')
            finally:
                self.shutdown_request(request)
            return
        self.pool.submit(self.run_request, request, client_address)

    def run_request(self, request, address):
        try:
            self.finish_request(request, address)
        except (BrokenPipeError, ConnectionError, TimeoutError, OSError):
            pass
        finally:
            self.shutdown_request(request)
            self.slots.release()

    def server_close(self):
        super().server_close()
        self.pool.shutdown(wait=True)


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "Player2WebBridge/0.1"
    sys_version = ""
    timeout = 15

    def log_message(self, *_):
        pass  # Default logging may contain caller-controlled URLs.

    def error(self, status, message):
        data = json.dumps({"error": {"message": message, "type": "local_bridge_error"}}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.forward()

    def do_POST(self):
        self.forward()

    def forward(self):
        port = self.server.server_port
        allowed_hosts = {"127.0.0.1:" + str(port), "localhost:" + str(port)}
        if self.headers.get("Host", "").lower() not in allowed_hosts or self.headers.get("Origin"):
            self.error(403, "This endpoint accepts native loopback clients only.")
            return
        if self.path not in ROUTES.get(self.command, set()):
            self.error(501, "This bridge does not implement that Player2 desktop endpoint.")
            return
        if self.headers.get("Transfer-Encoding"):
            self.error(400, "A Content-Length is required; chunked requests are unsupported.")
            return
        body = None
        if self.command == "POST":
            try:
                lengths = self.headers.get_all("Content-Length", [])
                if len(lengths) != 1:
                    raise ValueError()
                length = int(lengths[0])
                if not 0 < length <= MAX_BODY:
                    self.error(413, "Request exceeds the bridge's 32 MiB limit or is empty.")
                    return
                if self.headers.get_content_type() != "application/json":
                    self.error(415, "This endpoint requires JSON.")
                    return
                body = self.rfile.read(length)
                if len(body) != length:
                    raise ValueError()
                value = json.loads(body)
                if not isinstance(value, dict):
                    raise ValueError()
            except (ValueError, UnicodeError, TimeoutError):
                self.error(400, "Invalid or incomplete JSON request.")
                return
            if self.path == "/v1/tts/speak" and value.get("play_in_app"):
                self.error(501, "Desktop audio playback is unavailable; the caller must request audio bytes.")
                return
        headers = {"Authorization": "Bearer " + self.server.key,
                   "Accept": "application/json, text/event-stream", "Accept-Encoding": "identity",
                   "User-Agent": self.server_version}
        if body is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(self.server.upstream + self.path, data=body, headers=headers, method=self.command)
        started = time.monotonic()
        status = 502
        sent = 0
        headers_sent = False
        try:
            try:
                upstream = self.server.opener.open(request, timeout=120)
            except urllib.error.HTTPError as error:
                upstream = error  # Preserve actual upstream errors, including 401/402/429.
            with upstream:
                status = upstream.code
                if self.path == "/v1/health" and status == 200:
                    try:
                        health = json.loads(upstream.read(65536))
                        if not isinstance(health, dict):
                            raise ValueError()
                    except (ValueError, UnicodeError):
                        status = 502
                        self.error(status, "Player2 returned an invalid health response.")
                        return
                    # The mod checks for this field, absent from the Web API.
                    # Identify this bridge, never impersonate a desktop release.
                    health.update(client_version="player2-web-bridge/0.1", upstream="Player2 Web API")
                    data = json.dumps(health).encode()
                    self.send_response(status)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(data)))
                    self.send_header("Cache-Control", "no-store")
                    self.end_headers()
                    headers_sent = True
                    self.wfile.write(data)
                    sent = len(data)
                    return
                self.send_response(status)
                for name in ["Content-Type", "Content-Length", "Retry-After", "X-Player2-Trace-Id"]:
                    if upstream.headers.get(name):
                        self.send_header(name, upstream.headers[name])
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                headers_sent = True
                while chunk := upstream.read1(65536):
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    sent += len(chunk)
        except (urllib.error.URLError, TimeoutError, socket.timeout):
            if not headers_sent:
                self.error(502, "Player2 could not be reached or timed out; no automatic retry was made.")
        finally:
            print(json.dumps({"method": self.command, "route": self.path, "http": status,
                              "seconds": round(time.monotonic() - started, 3), "response_bytes": sent}), flush=True)


def read_key(path):
    info = path.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise ValueError("Credential file must be owned by this user and private (mode 0600).")
    data = json.loads(path.read_text())
    if data.get("client_id") != CLIENT_ID or not isinstance(data.get("p2Key"), str) or not data["p2Key"]:
        raise ValueError("Missing AI Influence Player2 authorization.")
    return data["p2Key"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--credentials", type=Path, required=True)
    parser.add_argument("--port", type=int, default=4315)
    args = parser.parse_args()
    os.umask(0o077)
    with Bridge(("127.0.0.1", args.port), read_key(args.credentials)) as server:
        print("Player2 Web API bridge listening on loopback port " + str(args.port), flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
