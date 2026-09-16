"""Loopback speech interface. It neither submits dialogue nor calls an LLM."""
import argparse
import hmac
import json
import math
import os
from pathlib import Path
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class SpeechServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, engine, runtime_dir, token):
        self.engine = engine
        self.runtime_dir = runtime_dir
        self.token = token
        self.recording = False
        self.generation = 0
        self.state_lock = threading.Lock()
        self.job_lock = threading.Lock()
        self.warmup_status = 'pending'
        self.warmup_thread = None
        super().__init__(address, SpeechHandler)

    def start_warmup(self):
        if self.warmup_thread is not None:
            return
        self.warmup_thread = threading.Thread(target=self._warmup, daemon=True)
        self.warmup_thread.start()

    def _warmup(self):
        started = time.monotonic()
        self.warmup_status = 'preparing'
        try:
            self.engine.warmup()
            self.warmup_status = 'ready'
        except Exception as error:
            self.warmup_status = 'failed'
            print(json.dumps({'operation': 'prepare', 'error_type': type(error).__name__}), flush=True)
        print(json.dumps({'operation': 'prepare', 'status': self.warmup_status, 'seconds': round(time.monotonic()-started, 3)}), flush=True)


VOICES = tuple('af_heart af_bella am_fenrir am_michael am_onyx am_puck bf_alice bf_emma bf_isabella bf_lily bm_daniel bm_fable bm_george bm_lewis'.split())


class SpeechHandler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def log_message(self, *_):
        pass  # Do not log microphone text or authorization headers.

    def reply(self, status, value, content_type='application/json'):
        data = value if isinstance(value, bytes) else json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        if self.headers.get('Origin'):
            return self.reply(403, {'error': 'Browser requests are not accepted'})
        if not hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + self.server.token):
            return self.reply(401, {'error': 'Speech session authorization required'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 20000:
                return self.reply(413, {'error': 'Invalid request size'})
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict):
                raise ValueError('Expected object')
        except (ValueError, TimeoutError):
            return self.reply(400, {'error': 'Invalid JSON request'})
        server = self.server
        try:
            if self.path == '/v1/dictation/cancel':
                with server.state_lock:
                    server.generation += 1
                    server.recording = False
                    server.engine.cancel()
                return self.reply(200, {'cancelled': True})
            if self.path == '/v1/dictation/start':
                with server.state_lock:
                    if server.recording or server.job_lock.locked():
                        return self.reply(409, {'error': 'Speech is already busy'})
                    server.engine.start()
                    server.recording = True
                    server.generation += 1
                return self.reply(200, {'recording': True, 'maximum_seconds': 30})
            if self.path == '/v1/dictation/stop':
                with server.state_lock:
                    if not server.recording or not server.job_lock.acquire(False):
                        return self.reply(409, {'error': 'No available recording'})
                    server.recording = False
                    generation = server.generation
                try:
                    text = server.engine.stop()
                    with server.state_lock:
                        if generation != server.generation:
                            text = ''
                    return self.reply(200, {'text': text})
                finally:
                    server.job_lock.release()
            if self.path == '/v1/speech':
                text, voice, speed = data.get('text'), data.get('voice', 'bm_george'), data.get('speed', 1.0)
                if (not isinstance(text, str) or not text.strip() or len(text) > 4000
                        or voice not in VOICES or isinstance(speed, bool) or not isinstance(speed, (float, int))
                        or not math.isfinite(speed) or not 0.8 <= speed <= 1.2):
                    return self.reply(400, {'error': 'Invalid speech text, voice or speed'})
                with server.state_lock:
                    if server.recording or not server.job_lock.acquire(False):
                        return self.reply(409, {'error': 'Speech is already busy'})
                started = time.monotonic()
                try:
                    audio = server.engine.synthesize(text.strip(), voice, float(speed))
                    server.warmup_status = 'ready'
                    print(json.dumps({'operation': 'synthesize', 'seconds': round(time.monotonic()-started, 3), 'characters': len(text), 'voice': voice}), flush=True)
                    return self.reply(200, audio, 'audio/wav')
                finally:
                    server.job_lock.release()
            return self.reply(404, {'error': 'Unknown operation'})
        except Exception as error:
            print(json.dumps({'operation': self.path, 'error_type': type(error).__name__}), flush=True)
            return self.reply(503, {'error': 'Local speech failed; text dialogue remains available'})

    def do_GET(self):
        if self.path == '/health':
            return self.reply(200, {'service': 'bannerlord-speech', 'version': 1, 'recording': self.server.recording, 'speech_status': self.server.warmup_status})
        if self.path == '/v1/voices':
            return self.reply(200, {'voices': [{'id': name, 'gender': 'female' if name[1] == 'f' else 'male', 'language': 'en-US' if name.startswith('a') else 'en-GB'} for name in VOICES]})
        return self.reply(404, {'error': 'Unknown operation'})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=11436)
    parser.add_argument('--runtime-dir', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    args.runtime_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    from engine import NativeEngine
    token = secrets.token_hex(32)
    engine = NativeEngine(args.runtime_dir)
    server = SpeechServer(('127.0.0.1', args.port), engine, args.runtime_dir, token)
    (args.runtime_dir / 'token').write_text(token)
    server.start_warmup()
    try:
        server.serve_forever()
    finally:
        engine.cancel()
        server.server_close()


if __name__ == '__main__':
    main()
