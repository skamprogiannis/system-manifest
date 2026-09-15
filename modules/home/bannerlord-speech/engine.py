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


class NativeEngine:
    def __init__(self, runtime_dir):
        self.runtime_dir = Path(runtime_dir)
        self.record_process = None
        self.record_dir = None
        self.worker = None
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

    def synthesize(self, text, voice, speed):
        if self.worker is None or self.worker.poll() is not None:
            self.worker = subprocess.Popen([sys.executable, __file__, '--tts-worker'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr, text=True, bufsize=1)
        try:
            self.worker.stdin.write(json.dumps({'text': text, 'voice': voice, 'speed': speed}) + '\n')
            self.worker.stdin.flush()
            with selectors.DefaultSelector() as selector:
                selector.register(self.worker.stdout, selectors.EVENT_READ)
                if not selector.select(45):
                    raise TimeoutError('Synthesis exceeded deadline')
                line = self.worker.stdout.readline()
            response = json.loads(line)
            if 'audio' not in response:
                raise RuntimeError('Synthesis failed')
            return base64.b64decode(response['audio'], validate=True)
        except Exception:
            self.worker.kill()
            self.worker.wait()
            self.worker = None
            raise


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
    pipeline = KPipeline(lang_code='b', model=model, device='cpu', repo_id='hexgrad/Kokoro-82M')
    for line in sys.stdin:
        try:
            request = json.loads(line)
            voice = Path(os.environ['KOKORO_VOICES']) / (request['voice'] + '.pt')
            chunks = [result.audio.numpy() for result in pipeline(request['text'], voice=str(voice), speed=request['speed']) if result.audio is not None]
            if not chunks:
                raise ValueError('No audio')
            buffer = io.BytesIO()
            sf.write(buffer, np.concatenate(chunks), 24000, format='WAV', subtype='PCM_16')
            response = {'audio': base64.b64encode(buffer.getvalue()).decode('ascii')}
        except Exception as error:
            response = {'error': type(error).__name__}
        protocol.write(json.dumps(response) + '\n')
        protocol.flush()


if __name__ == '__main__' and sys.argv[1:] == ['--tts-worker']:
    tts_worker()
