#!/usr/bin/env python3
"""Use Player2's documented device authorization flow; keep keys on this machine."""
import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CLIENT_ID = "0199bcdd-3f9f-7a67-947e-ca10021b94ce"
BASE = "https://api.player2.game/v1"


def call(route, payload=None, key=None):
    headers = {"Accept": "application/json"}
    if key:
        headers["Authorization"] = "Bearer " + key
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode()
    request = urllib.request.Request(BASE + route, data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read(16384)
        try:
            value = json.loads(body)
        except ValueError:
            value = {"error": "non_json_response"}
        return error.code, value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--credentials", type=Path, required=True)
    args = parser.parse_args()
    target = args.credentials
    state = target.parent
    os.umask(0o077)
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    state.chmod(0o700)
    if target.exists():
        raise RuntimeError("Existing credentials preserved; verify before starting another authorization")
    status, flow = call("/login/device/new", {"client_id": CLIENT_ID})
    if status != 200:
        raise RuntimeError("Device authorization initialization failed: HTTP " + str(status))
    url = flow["verificationUriComplete"]
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname != "player2.game":
        raise RuntimeError("Unexpected authorization host")
    print("Authorize AI Influence in your browser. Code: " + flow["userCode"], flush=True)
    print("Authorization URL: " + url, flush=True)
    subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    interval = max(1, int(flow["interval"]))
    deadline = time.monotonic() + int(flow["expiresIn"])
    while time.monotonic() < deadline:
        time.sleep(interval)
        status, response = call("/login/device/token", {
            "client_id": CLIENT_ID,
            "device_code": flow["deviceCode"],
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        })
        key = response.get("p2Key") if isinstance(response, dict) else None
        if status == 200 and isinstance(key, str) and key:
            with target.open("x") as output:
                json.dump({"client_id": CLIENT_ID, "p2Key": key}, output)
            target.chmod(0o600)
            health, _ = call("/health", key=key)
            balance_status, balance = call("/joules", key=key)
            safe_balance = {k: balance[k] for k in ["joules", "patron_tier"] if k in balance}
            print(json.dumps({"authorized": True, "health_http": health, "balance_http": balance_status, "balance": safe_balance}), flush=True)
            return 0
        error = response.get("error") if isinstance(response, dict) else None
        if status == 429 or error == "slow_down":
            interval += 5
        elif status == 400 and error == "authorization_pending":
            continue
        else:
            raise RuntimeError("Device authorization polling failed: HTTP " + str(status) + "; " + str(error))
    raise RuntimeError("Device authorization expired")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
