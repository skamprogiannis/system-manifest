"""Manage the on-demand user service without sending inference requests."""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

UNIT = "bannerlord-codex.service"
HEALTH_URL = "http://127.0.0.1:11435/healthz"


def health(url=HEALTH_URL):
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(url, timeout=1) as response:
            if response.status != 200:
                return None
            data = json.loads(response.read(4097))
        if (isinstance(data, dict) and data.get("adapter_ready") is True
                and data.get("account_and_quota_verified") is False
                and isinstance(data.get("model"), str)):
            return data
    except (OSError, ValueError, urllib.error.URLError):
        pass
    return None


def active():
    result = subprocess.run(["systemctl", "--user", "is-active", "--quiet", UNIT],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    return result.returncode == 0


def report(data):
    print("Adapter ready on 127.0.0.1:11435; model: " + data["model"])
    print("Account access and quota are not verified by this health check. No inference was sent.")


def main(args):
    action = args[0] if args else "status"
    if len(args) > 1 or action not in ("start", "stop", "status"):
        print("Usage: bannerlord-codex start|stop|status", file=sys.stderr)
        return 2
    if action == "stop":
        result = subprocess.run(["systemctl", "--user", "stop", UNIT], timeout=15)
        if result.returncode == 0:
            print("Bannerlord Codex adapter stopped, including its active request processes.")
        return result.returncode
    if action == "start":
        result = subprocess.run(["systemctl", "--user", "start", UNIT], timeout=35)
        if result.returncode:
            print("Adapter did not start. Inspect: journalctl --user -u " + UNIT, file=sys.stderr)
            return result.returncode
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            data = health()
            if data and active():
                report(data)
                return 0
            time.sleep(0.2)
        print("Adapter readiness failed. Inspect: journalctl --user -u " + UNIT, file=sys.stderr)
        return 1
    if not active():
        print("Bannerlord Codex adapter is inactive. Start it with: bannerlord-codex start")
        return 3
    data = health()
    if data:
        report(data)
        return 0
    print("Service is active but its adapter is not ready.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (OSError, subprocess.TimeoutExpired):
        print("Could not complete the user-service operation.", file=sys.stderr)
        raise SystemExit(1)
