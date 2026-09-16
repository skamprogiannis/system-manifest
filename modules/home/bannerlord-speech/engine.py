"""Native bounded audio processes. No recording occurs during initialization."""
import base64
import io
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile
import threading
import time
import wave


class SpeechCancelled(Exception):
    pass


def split_speech_text(text, limit=120):
    parts = []
    remaining = text.strip()
    while len(remaining) > limit:
        prefix = remaining[:limit + 1]
        punctuation = max((prefix.rfind(mark) + 1 for mark in ('. ', '? ', '! ', '; ', ': ', ', ')), default=0)
        end = punctuation if punctuation >= limit // 3 else prefix.rfind(' ')
        if end <= 0:
            end = limit
        parts.append(remaining[:end].strip())
        remaining = remaining[end:].lstrip()
    if remaining:
        parts.append(remaining)
    return parts


def render_speech_parts(pipeline, text, voice, speed, cancelled):
    chunks = []
    for part in split_speech_text(text):
        if cancelled():
            raise SpeechCancelled()
        for result in pipeline(part, voice=voice, speed=speed):
            if cancelled():
                raise SpeechCancelled()
            if result.audio is not None:
                chunks.append(result.audio.numpy())
    if cancelled():
        raise SpeechCancelled()
    return chunks


class NativeEngine:
    def __init__(self, runtime_dir):
        self.runtime_dir = Path(runtime_dir)
        self.record_process = None
        self.record_dir = None
        self.worker = None
        self.worker_lock = threading.Lock()
        self.record_lock = threading.RLock()
        self.timer = None

    def start(self):
        with self.record_lock:
            self.cancel()
            self.record_dir = tempfile.TemporaryDirectory(prefix='record-', dir=self.runtime_dir)
            path = str(Path(self.record_dir.name) / 'speech.wav')
            self.record_process = subprocess.Popen([os.environ['PW_RECORD_BIN'], '--rate=16000', '--channels=1', '--format=s16', path], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(0.12)
            if self.record_process.poll() is not None:
                self.cancel()
                raise RuntimeError('Microphone could not start')
            self.timer = threading.Timer(30, self._finish_recording)
            self.timer.daemon = True
            self.timer.start()

    def _finish_recording(self):
        with self.record_lock:
            if self.record_process is not None and self.record_process.poll() is None:
                self.record_process.send_signal(signal.SIGINT)
                try:
                    self.record_process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.record_process.kill()
                    self.record_process.wait()

    def cancel(self):
        with self.record_lock:
            if self.timer:
                self.timer.cancel()
                self.timer = None
            self._finish_recording()
            self.record_process = None
            if self.record_dir:
                self.record_dir.cleanup()
                self.record_dir = None

    def stop(self):
        with self.record_lock:
            if self.record_dir is None:
                return ''
            self._finish_recording()
            if self.timer:
                self.timer.cancel()
            # Transfer ownership so a later cancel cannot delete the input mid-read.
            recording, self.record_dir = self.record_dir, None
            self.record_process = None
        try:
            path = Path(recording.name) / 'speech.wav'
            with wave.open(str(path), 'rb') as wav:
                raw = wav.readframes(wav.getnframes())
                duration = wav.getnframes() / wav.getframerate()
            import array
            samples = array.array('h', raw)
            if duration < 0.25 or not samples or sum(x*x for x in samples)/len(samples) < 10000:
                return ''
            output = Path(recording.name) / 'transcript'
            subprocess.run([os.environ['WHISPER_BIN'], '-m', os.environ['WHISPER_MODEL'], '-f', str(path), '-l', 'en', '-t', '2', '-nt', '-otxt', '-of', str(output)], check=True, timeout=35, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            text = output.with_suffix('.txt').read_text().strip()
            if text.lower() in ('[blank_audio]', '[silence]', '(silence)', '[music]'):
                return ''
            return text
        finally:
            recording.cleanup()

    def warmup(self):
        # Load model/frontend only: no microphone, utterance or playback.
        response = self._worker_request({'operation': 'prepare'})
        if response.get('ready') is not True:
            raise RuntimeError('Speech preparation failed')

    def synthesize(self, text, voice, speed, cancel_event=None, audio_format='wav'):
        with tempfile.TemporaryDirectory(prefix='speech-', dir=self.runtime_dir) as temporary:
            cancel_path = Path(temporary) / 'cancel'
            response = self._worker_request({'text': text, 'voice': voice, 'speed': speed, 'cancel_path': str(cancel_path), 'format': audio_format}, cancel_event=cancel_event, cancel_path=cancel_path)
        if 'audio' not in response:
            raise RuntimeError('Synthesis failed')
        return base64.b64decode(response['audio'], validate=True)

    def _worker_request(self, request, *, cancel_event=None, cancel_path=None):
        # Preparation and synthesis share one process and its line protocol.
        deadline = time.monotonic() + 45
        if cancel_event is None:
            acquired = self.worker_lock.acquire(timeout=45)
        else:
            acquired = False
            while not acquired and time.monotonic() < deadline:
                if cancel_event.is_set():
                    raise SpeechCancelled()
                acquired = self.worker_lock.acquire(timeout=min(.1, max(0, deadline - time.monotonic())))
        if not acquired:
            raise TimeoutError('Speech preparation exceeded deadline')
        try:
            if cancel_event is not None and cancel_event.is_set():
                raise SpeechCancelled()
            if self.worker is None or self.worker.poll() is not None:
                self.worker = subprocess.Popen([sys.executable, __file__, '--tts-worker'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr, text=True, bufsize=1)
            try:
                self.worker.stdin.write(json.dumps(request) + '\n')
                self.worker.stdin.flush()
                with selectors.DefaultSelector() as selector:
                    selector.register(self.worker.stdout, selectors.EVENT_READ)
                    while True:
                        remaining = deadline - time.monotonic()
                        if remaining <= 0:
                            raise TimeoutError('Synthesis exceeded deadline')
                        if cancel_event is not None and cancel_event.is_set():
                            cancel_path.touch(exist_ok=True)
                        if selector.select(min(.1, remaining) if cancel_event is not None else remaining):
                            break
                        if cancel_event is None:
                            raise TimeoutError('Synthesis exceeded deadline')
                    line = self.worker.stdout.readline()
                response = json.loads(line)
                if response.get('cancelled') is True:
                    raise SpeechCancelled()
                if 'error' in response:
                    raise RuntimeError('Synthesis failed')
                return response
            except SpeechCancelled:
                raise
            except Exception:
                self.worker.kill()
                self.worker.wait()
                self.worker = None
                raise
        finally:
            self.worker_lock.release()


def pipeline_for_voice(voice, pipelines, model, factory):
    language = voice[:1]
    if language not in ('a', 'b'):
        raise ValueError('Unsupported English voice')
    if language not in pipelines:
        pipelines[language] = factory(lang_code=language, model=model, device='cpu', repo_id='hexgrad/Kokoro-82M')
    return pipelines[language]


def tts_worker():
    # Restrict numerical libraries before importing Torch.
    os.environ['OMP_NUM_THREADS'] = '2'
    os.environ['MKL_NUM_THREADS'] = '2'
    protocol = sys.stdout
    sys.stdout = sys.stderr
    import numpy as np
    import soundfile as sf
    import torch
    from kokoro import KModel, KPipeline
    torch.set_num_threads(2)
    torch.set_num_interop_threads(1)
    model = KModel(repo_id='hexgrad/Kokoro-82M', config=os.environ['KOKORO_CONFIG'], model=os.environ['KOKORO_MODEL']).eval().to('cpu')
    pipelines = {}
    pipeline_for_voice('bm_george', pipelines, model, KPipeline)
    for line in sys.stdin:
        try:
            request = json.loads(line)
            if request.get('operation') == 'prepare':
                protocol.write(json.dumps({'ready': True}) + '\n')
                protocol.flush()
                continue
            pipeline = pipeline_for_voice(request['voice'], pipelines, model, KPipeline)
            voice = Path(os.environ['KOKORO_VOICES']) / (request['voice'] + '.pt')
            cancel_path = Path(request['cancel_path']) if request.get('cancel_path') else None
            chunks = render_speech_parts(pipeline, request['text'], str(voice), request['speed'], lambda: cancel_path is not None and cancel_path.exists())
            if not chunks:
                raise ValueError('No audio')
            buffer = io.BytesIO()
            audio_format = request.get('format', 'wav')
            if audio_format not in ('wav', 'ogg'):
                raise ValueError('Unsupported audio format')
            sf.write(buffer, np.concatenate(chunks), 24000, format='OGG' if audio_format == 'ogg' else 'WAV', subtype='VORBIS' if audio_format == 'ogg' else 'PCM_16')
            response = {'audio': base64.b64encode(buffer.getvalue()).decode('ascii')}
        except SpeechCancelled:
            response = {'cancelled': True}
        except Exception as error:
            response = {'error': type(error).__name__}
        protocol.write(json.dumps(response) + '\n')
        protocol.flush()


if __name__ == '__main__' and sys.argv[1:] == ['--tts-worker']:
    tts_worker()
