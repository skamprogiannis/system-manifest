"""On-demand launcher control; never records, plays audio or prints a token."""
import json
import subprocess
import sys
import time
import urllib.request

UNIT = 'bannerlord-speech.service'


def healthy():
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open('http://127.0.0.1:11436/health', timeout=1) as response:
            return json.load(response).get('service') == 'bannerlord-speech'
    except (OSError, ValueError):
        return False


def main():
    command = sys.argv[1] if len(sys.argv) == 2 else 'help'
    if command == 'start':
        subprocess.run(['systemctl', '--user', 'start', UNIT], check=True)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if healthy():
                print('Local speech connected; voices prepare in the background; microphone idle.')
                return 0
            time.sleep(0.25)
        print('Local speech did not become ready.', file=sys.stderr)
        return 1
    if command == 'stop':
        subprocess.run(['systemctl', '--user', 'stop', UNIT], check=True)
        return 0
    if command == 'status':
        ready = healthy()
        print('ready' if ready else 'stopped')
        return 0 if ready else 1
    print('Usage: bannerlord-speech start|stop|status')
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
