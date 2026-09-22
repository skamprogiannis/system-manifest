"""Private, on-demand desktop dictation backed by the local Whisper service."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request

PORT = 11437
UNIT = 'desktop-dictation.service'
GAME_UNIT = 'bannerlord-speech.service'


def runtime_dir():
    value = os.environ.get('XDG_RUNTIME_DIR')
    if not value:
        raise RuntimeError('No user runtime directory is available')
    return Path(value) / 'desktop-dictation'


def state_path():
    return runtime_dir() / 'recording'


def notify(summary, body=''):
    subprocess.run(['notify-send', '-a', 'Dictation', summary, body], check=False,
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def run_systemctl(*args):
    return subprocess.run(['systemctl', '--user', *args], check=False,
                          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def game_is_open():
    return subprocess.run(['pgrep', '-f', r'[/\\]Bannerlord\.exe(?: |$)'], check=False,
                          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def token():
    path = runtime_dir() / 'token'
    try:
        value = path.read_text().strip()
    except OSError:
        return ''
    return value if len(value) == 64 and all(character in '0123456789abcdef' for character in value) else ''


def request(path, payload, timeout=40):
    secret = token()
    if not secret:
        raise RuntimeError('Dictation service did not become ready')
    body = json.dumps(payload, separators=(',', ':')).encode()
    request = urllib.request.Request(
        f'http://127.0.0.1:{PORT}{path}', body,
        headers={'Authorization': 'Bearer ' + secret, 'Content-Type': 'application/json'},
        method='POST')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(request, timeout=timeout) as response:
            return json.load(response)
    except (OSError, ValueError, urllib.error.HTTPError) as error:
        raise RuntimeError('Local dictation failed') from error


def wait_until_ready():
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if token():
            return
        time.sleep(.05)
    raise RuntimeError('Dictation service did not become ready')


def stop_service():
    run_systemctl('stop', UNIT)


def start():
    if game_is_open() or run_systemctl('is-active', '--quiet', GAME_UNIT).returncode == 0:
        notify('Dictation unavailable', 'Close Bannerlord before using desktop dictation.')
        return 1
    if state_path().exists():
        return 0
    if run_systemctl('start', UNIT).returncode != 0:
        notify('Dictation unavailable', 'The local service could not start.')
        return 1
    try:
        wait_until_ready()
        request('/v1/dictation/start', {}, timeout=8)
        state_path().write_text('recording\n')
        state_path().chmod(0o600)
        notify('Listening…', 'Release Super+T when you are finished.')
        return 0
    except RuntimeError:
        stop_service()
        notify('Dictation unavailable', 'The microphone or local transcription service could not start.')
        return 1


def stop():
    state = state_path()
    if not state.exists():
        return 0
    try:
        response = request('/v1/dictation/stop', {}, timeout=40)
        text = response.get('text', '') if isinstance(response, dict) else ''
        if not isinstance(text, str) or not text.strip():
            notify('No speech detected')
            return 0
        subprocess.run(['wl-copy'], input=text.encode(), check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        notify('Transcription copied', 'Paste it where you need it.')
        return 0
    except (OSError, RuntimeError, subprocess.SubprocessError):
        notify('Transcription failed', 'No text was copied.')
        return 1
    finally:
        try:
            state.unlink(missing_ok=True)
        finally:
            stop_service()


def cancel():
    state = state_path()
    if not state.exists():
        return 0
    try:
        request('/v1/dictation/cancel', {}, timeout=8)
    except RuntimeError:
        pass
    finally:
        state.unlink(missing_ok=True)
        stop_service()
    notify('Dictation cancelled')
    return 0


def main():
    command = sys.argv[1] if len(sys.argv) == 2 else ''
    if command == 'start':
        return start()
    if command == 'stop':
        return stop()
    if command == 'cancel':
        return cancel()
    print('Usage: desktop-dictation start|stop|cancel', file=sys.stderr)
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
