"""Loopback speech interface. It neither submits dialogue nor calls an LLM."""
import argparse
from collections import OrderedDict
import hashlib
import io
import hmac
import json
import math
import os
from pathlib import Path
import secrets
import re
import sys
import tempfile
import wave
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from engine import SpeechCancelled


class SpeechCache:
    """Private bounded audio cache; names hash content instead of exposing dialogue."""
    def __init__(self, directory, limit=256 * 1024 * 1024):
        self.directory, self.limit = Path(directory), limit
        self.lock = threading.Lock()
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.directory.chmod(0o700)
        self._prune()

    def key(self, text, voice, speed, audio_format):
        voice_file = Path(os.environ.get('KOKORO_VOICES', '')) / (voice + '.pt')
        identity = [1, sys.executable, os.environ.get('KOKORO_MODEL'), os.environ.get('KOKORO_CONFIG'), str(voice_file.resolve()), text, voice, speed, audio_format]
        return hashlib.sha256(json.dumps(identity, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()

    @staticmethod
    def valid(audio, audio_format):
        try:
            if audio_format == 'ogg':
                import soundfile
                info = soundfile.info(io.BytesIO(audio))
                return info.format == 'OGG' and info.subtype == 'VORBIS' and info.channels == 1 and info.samplerate == 24000 and info.frames > 0
            with wave.open(io.BytesIO(audio), 'rb') as wav:
                return wav.getnchannels() == 1 and wav.getsampwidth() == 2 and wav.getframerate() == 24000 and wav.getnframes() > 0 and len(wav.readframes(wav.getnframes())) == wav.getnframes() * 2
        except (EOFError, ValueError, RuntimeError, wave.Error):
            return False

    def get(self, key, audio_format):
        path = self.directory / (key + '.' + audio_format)
        with self.lock:
            try:
                if path.is_symlink() or not path.is_file() or path.stat().st_size > min(self.limit, 32 * 1024 * 1024):
                    return None
                audio = path.read_bytes()
                if not self.valid(audio, audio_format):
                    path.unlink(missing_ok=True)
                    return None
                try:
                    os.utime(path, None)
                except OSError:
                    pass
                return audio
            except OSError:
                return None

    def put(self, key, audio, audio_format):
        if len(audio) > min(self.limit, 32 * 1024 * 1024) or not self.valid(audio, audio_format):
            return
        with self.lock:
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(dir=self.directory, prefix='.audio-', delete=False) as output:
                    temporary = Path(output.name)
                    output.write(audio)
                temporary.replace(self.directory / (key + '.' + audio_format))
                self._prune()
            except OSError:
                print(json.dumps({'operation': 'speech_cache', 'status': 'write_failed'}), flush=True)
            finally:
                if temporary:
                    try:
                        temporary.unlink(missing_ok=True)
                    except OSError:
                        pass

    def _prune(self):
        entries = []
        for path in self.directory.iterdir():
            if re.fullmatch(r'[0-9a-f]{64}\.(wav|ogg)', path.name) and not path.is_symlink():
                try:
                    item = path.stat()
                    entries.append((item.st_mtime_ns, path, item.st_size))
                except OSError:
                    pass
        entries.sort()
        total, count = sum(item[2] for item in entries), len(entries)
        for _, path, size in entries:
            if total <= self.limit and count <= 2048:
                break
            try:
                path.unlink(missing_ok=True)
                total -= size; count -= 1
            except OSError:
                pass


class SpeechServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, engine, runtime_dir, token, *, cache_dir=None, cache_limit=256 * 1024 * 1024):
        self.engine = engine
        self.runtime_dir = runtime_dir
        self.token = token
        self.recording = False
        self.generation = 0
        self.state_lock = threading.Lock()
        self.job_lock = threading.Lock()
        self.warmup_status = 'pending'
        self.warmup_thread = None
        self.cache = None
        if cache_dir:
            try:
                self.cache = SpeechCache(cache_dir, cache_limit)
            except OSError:
                print(json.dumps({'operation': 'speech_cache', 'status': 'unavailable'}), flush=True)
        self.active_speech = {}
        self.cancelled_requests = OrderedDict()
        super().__init__(address, SpeechHandler)

    def cancelled_locked(self, request_id):
        now = time.monotonic()
        while self.cancelled_requests and next(iter(self.cancelled_requests.values())) < now:
            self.cancelled_requests.popitem(last=False)
        return request_id in self.cancelled_requests

    def cancel_speech(self, request_id):
        with self.state_lock:
            self.cancelled_locked(request_id)
            self.cancelled_requests.pop(request_id, None)
            self.cancelled_requests[request_id] = time.monotonic() + 120
            while len(self.cancelled_requests) > 1024:
                self.cancelled_requests.popitem(last=False)
            event = self.active_speech.get(request_id)
            if event is not None:
                event.set()
            return event is not None

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

    def reply(self, status, value, content_type='application/json', headers=None):
        data = value if isinstance(value, bytes) else json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        for name, value in (headers or {}).items():
            self.send_header(name, value)
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
            if self.path == '/v1/speech/cancel':
                request_id = data.get('request_id')
                if not self.valid_request_id(request_id):
                    return self.reply(400, {'error': 'Invalid speech request ID'})
                return self.reply(200, {'cancelled': True, 'active': server.cancel_speech(request_id)})
            if self.path == '/v1/speech':
                return self.speech(data)
            return self.reply(404, {'error': 'Unknown operation'})
        except Exception as error:
            print(json.dumps({'operation': self.path, 'error_type': type(error).__name__}), flush=True)
            return self.reply(503, {'error': 'Local speech failed; text dialogue remains available'})

    @staticmethod
    def valid_request_id(value):
        return isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,80}', value) is not None

    def speech(self, data):
        started = time.monotonic()
        text, voice, speed = data.get('text'), data.get('voice', 'bm_george'), data.get('speed', 1.0)
        request_id = data.get('request_id')
        audio_format = data.get('format', 'wav')
        if (audio_format not in ('wav', 'ogg') or not isinstance(text, str) or not text.strip() or len(text) > 4000
                or voice not in VOICES or isinstance(speed, bool) or not isinstance(speed, (float, int))
                or not math.isfinite(speed) or not 0.8 <= speed <= 1.2
                or (request_id is not None and not self.valid_request_id(request_id))):
            return self.reply(400, {'error': 'Invalid speech text, voice, speed or request ID'})
        text, speed = text.strip(), float(speed)
        server = self.server
        with server.state_lock:
            if server.cancelled_locked(request_id):
                return self.reply(409, {'code': 'cancelled', 'error': 'Speech request was cancelled'})
            if server.recording:
                return self.reply(409, {'code': 'busy', 'error': 'Speech is already busy'})
        key = server.cache.key(text, voice, speed, audio_format) if server.cache else None
        audio = server.cache.get(key, audio_format) if server.cache else None
        cancel_event = threading.Event()
        with server.state_lock:
            if server.cancelled_locked(request_id):
                return self.reply(409, {'code': 'cancelled', 'error': 'Speech request was cancelled'})
            if server.recording or (audio is None and not server.job_lock.acquire(False)):
                return self.reply(409, {'code': 'busy', 'error': 'Speech is already busy'})
            if audio is None and request_id is not None:
                server.active_speech[request_id] = cancel_event
        if audio is not None:
            print(json.dumps({'operation': 'synthesize', 'cache': 'hit', 'seconds': round(time.monotonic()-started, 3), 'characters': len(text), 'voice': voice, 'format': audio_format}), flush=True)
            return self.reply(200, audio, 'audio/ogg' if audio_format == 'ogg' else 'audio/wav', {'X-Speech-Cache': 'hit'})
        started = time.monotonic()
        try:
            options = {'cancel_event': cancel_event} if request_id is not None else {}
            if audio_format == 'ogg':
                options['audio_format'] = audio_format
            audio = server.engine.synthesize(text, voice, speed, **options)
            if cancel_event.is_set():
                raise SpeechCancelled()
            server.warmup_status = 'ready'
            if server.cache:
                server.cache.put(key, audio, audio_format)
            print(json.dumps({'operation': 'synthesize', 'cache': 'miss', 'seconds': round(time.monotonic()-started, 3), 'characters': len(text), 'voice': voice, 'format': audio_format}), flush=True)
            return self.reply(200, audio, 'audio/ogg' if audio_format == 'ogg' else 'audio/wav', {'X-Speech-Cache': 'miss'})
        except SpeechCancelled:
            return self.reply(409, {'code': 'cancelled', 'error': 'Speech request was cancelled'})
        finally:
            with server.state_lock:
                if request_id is not None:
                    server.active_speech.pop(request_id, None)
                server.job_lock.release()

    def do_GET(self):
        if self.path == '/health':
            return self.reply(200, {'service': 'bannerlord-speech', 'version': 1, 'recording': self.server.recording, 'speech_status': self.server.warmup_status, 'audio_formats': ['wav', 'ogg'], 'speech_cancel_supported': True, 'cache_enabled': self.server.cache is not None})
        if self.path == '/v1/voices':
            return self.reply(200, {'voices': [{'id': name, 'gender': 'female' if name[1] == 'f' else 'male', 'language': 'en-US' if name.startswith('a') else 'en-GB'} for name in VOICES]})
        return self.reply(404, {'error': 'Unknown operation'})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=11436)
    parser.add_argument('--runtime-dir', type=Path, required=True)
    parser.add_argument('--cache-dir', type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    args.runtime_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    from engine import NativeEngine
    token = secrets.token_hex(32)
    engine = NativeEngine(args.runtime_dir)
    server = SpeechServer(('127.0.0.1', args.port), engine, args.runtime_dir, token, cache_dir=args.cache_dir)
    (args.runtime_dir / 'token').write_text(token)
    server.start_warmup()
    try:
        server.serve_forever()
    finally:
        engine.cancel()
        server.server_close()


if __name__ == '__main__':
    main()
