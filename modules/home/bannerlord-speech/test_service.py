import http.client
import io
import wave
from unittest.mock import patch
import json
import tempfile
import threading
import unittest
from pathlib import Path

from service import SpeechServer


class FakeEngine:
    def __init__(self):
        self.recording = False
        self.calls = []

    def start(self):
        self.recording = True

    def stop(self):
        self.recording = False
        return 'What paid service do you need?'

    def cancel(self):
        self.recording = False

    def synthesize(self, text, voice, speed):
        self.calls.append((text, voice, speed))
        return b'RIFF\x24\x00\x00\x00WAVE'


class SpeechInterfaceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.engine = FakeEngine()
        self.server = SpeechServer(('127.0.0.1', 0), self.engine, Path(self.tmp.name), 'test-token')
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.tmp.cleanup()

    def request(self, method, path, value=None, token='test-token', origin=None):
        conn = http.client.HTTPConnection(*self.server.server_address, timeout=3)
        headers = {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}
        if origin:
            headers['Origin'] = origin
        conn.request(method, path, None if value is None else json.dumps(value), headers)
        response = conn.getresponse()
        data = response.read()
        status = response.status
        conn.close()
        return status, data

    def test_microphone_requires_session_token_and_rejects_browser_origin(self):
        self.assertEqual(self.request('POST', '/v1/dictation/start', {}, token='bad')[0], 401)
        self.assertEqual(self.request('POST', '/v1/dictation/start', {}, origin='https://example.com')[0], 403)
        self.assertFalse(self.engine.recording)

    def test_dictation_returns_draft_without_sending_a_conversation(self):
        self.assertEqual(self.request('POST', '/v1/dictation/start', {})[0], 200)
        self.assertTrue(self.engine.recording)
        status, data = self.request('POST', '/v1/dictation/stop', {})
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(data)['text'], 'What paid service do you need?')
        self.assertFalse(self.engine.recording)
        self.assertEqual(self.engine.calls, [])

    def test_second_start_does_not_create_another_recording_and_cancel_is_idempotent(self):
        self.request('POST', '/v1/dictation/start', {})
        self.assertEqual(self.request('POST', '/v1/dictation/start', {})[0], 409)
        for _ in range(2):
            self.assertEqual(self.request('POST', '/v1/dictation/cancel', {})[0], 200)
        self.assertFalse(self.engine.recording)
        self.assertEqual(self.request('POST', '/v1/dictation/stop', {})[0], 409)

    def test_voice_catalog_and_synthesis_do_not_use_character_names_as_paths(self):
        status, data = self.request('GET', '/v1/voices')
        self.assertEqual(status, 200)
        voices = json.loads(data)['voices']
        self.assertEqual(len(voices), 14)
        self.assertEqual({voice["id"]: voice["language"] for voice in voices}["am_fenrir"], "en-US")
        self.assertEqual({voice["id"]: voice["language"] for voice in voices}["bm_lewis"], "en-GB")
        self.assertEqual(self.request('POST', '/v1/speech', {'text': 'Welcome.', 'voice': '../../file'})[0], 400)
        status, wav = self.request('POST', '/v1/speech', {'text': 'Welcome.', 'voice': 'bm_george'})
        self.assertEqual(status, 200)
        self.assertTrue(wav.startswith(b'RIFF'))
        self.assertEqual(self.engine.calls, [('Welcome.', 'bm_george', 1.0)])

    def test_failed_recording_is_recoverable_and_does_not_expose_internal_paths(self):
        def fail():
            raise RuntimeError('/private/path microphone unavailable')
        self.engine.start = fail
        status, data = self.request('POST', '/v1/dictation/start', {})
        self.assertEqual(status, 503)
        self.assertNotIn(b'/private/path', data)
        self.assertEqual(self.request('POST', '/v1/dictation/cancel', {})[0], 200)

    def test_model_preparation_does_not_block_health_or_dictation(self):
        started, release = threading.Event(), threading.Event()
        def prepare():
            started.set()
            if not release.wait(3):
                raise TimeoutError('Fixture was not released')
        self.engine.warmup = prepare
        try:
            self.server.start_warmup()
            self.assertTrue(started.wait(1))
            status, data = self.request('GET', '/health')
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(data)['speech_status'], 'preparing')
            self.assertFalse(self.engine.recording)
            self.assertEqual(self.request('POST', '/v1/dictation/start', {})[0], 200)
            self.assertEqual(self.request('POST', '/v1/dictation/stop', {})[0], 200)
        finally:
            release.set()
            self.server.warmup_thread.join(2)
        self.assertEqual(self.server.warmup_status, 'ready')
        self.assertEqual(self.engine.calls, [])

    def test_failed_preparation_keeps_dictation_and_speech_recovery_available(self):
        def fail():
            raise RuntimeError('Fixture load failed')
        self.engine.warmup = fail
        self.server.start_warmup()
        self.server.warmup_thread.join(2)
        self.assertEqual(self.server.warmup_status, 'failed')
        self.assertEqual(self.request('POST', '/v1/dictation/start', {})[0], 200)
        self.assertEqual(self.request('POST', '/v1/dictation/stop', {})[0], 200)
        self.assertEqual(self.request('POST', '/v1/speech', {'text': 'Welcome.'})[0], 200)

    def test_invalid_speech_is_not_generated(self):
        for payload in ({'text': ''}, {'text': 'x' * 4001}, {'text': 'Hello', 'speed': float('nan')}):
            self.assertEqual(self.request('POST', '/v1/speech', payload)[0], 400)
        self.assertEqual(self.engine.calls, [])


class SpeechCacheAndCancellationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache_dir = Path(self.tmp.name) / 'cache'
        self.environment = patch.dict('os.environ', {'KOKORO_MODEL': 'fixture-model-v1', 'KOKORO_CONFIG': 'fixture-config', 'KOKORO_VOICES': str(Path(self.tmp.name) / 'voices')})
        self.environment.start()
        output = io.BytesIO()
        with wave.open(output, 'wb') as wav:
            wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(24000)
            wav.writeframes(b'\0' * 16)
        self.audio = output.getvalue()
        self.start_server()

    def start_server(self, limit=256 * 1024 * 1024):
        self.engine = FakeEngine()
        def synthesize(text, voice, speed, cancel_event=None):
            self.engine.calls.append((text, voice, speed))
            return self.audio
        self.engine.synthesize = synthesize
        self.server = SpeechServer(('127.0.0.1', 0), self.engine, Path(self.tmp.name), 'test-token', cache_dir=self.cache_dir, cache_limit=limit)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={'poll_interval': .01}, daemon=True)
        self.thread.start()

    def stop_server(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()

    def tearDown(self):
        self.stop_server(); self.environment.stop(); self.tmp.cleanup()

    def request(self, path, value):
        conn = http.client.HTTPConnection(*self.server.server_address, timeout=3)
        conn.request('POST', path, json.dumps(value), {'Authorization': 'Bearer test-token', 'Content-Type': 'application/json'})
        response = conn.getresponse()
        result = response.status, response.read(), dict(response.getheaders())
        conn.close()
        return result

    def speak(self, text='Welcome.', **options):
        return self.request('/v1/speech', {'text': text, 'voice': 'bm_lewis', **options})

    def test_repeated_speech_is_cached_across_service_restart(self):
        first = self.speak(request_id='first')
        self.assertEqual(first[0], 200)
        self.assertEqual(first[2]['X-Speech-Cache'], 'miss')
        second = self.speak(request_id='second')
        self.assertEqual(second[1], first[1])
        self.assertEqual(second[2]['X-Speech-Cache'], 'hit')
        self.assertEqual(len(self.engine.calls), 1)
        self.stop_server(); self.start_server()
        self.assertEqual(self.speak()[2]['X-Speech-Cache'], 'hit')
        self.assertEqual(self.engine.calls, [])
        self.assertTrue(all(p.stat().st_mode & 0o077 == 0 for p in self.cache_dir.iterdir()))
        self.assertTrue(all('Welcome' not in p.name for p in self.cache_dir.iterdir()))

    def test_cache_key_separates_text_voice_speed_and_model(self):
        for options in ({}, {'text':'Another line.'}, {'voice':'bm_george'}, {'speed':1.1}):
            self.assertEqual(self.speak(**options)[0], 200)
        self.assertEqual(len(self.engine.calls), 4)
        with patch.dict('os.environ', {'KOKORO_MODEL':'fixture-model-v2'}):
            self.assertEqual(self.speak()[2]['X-Speech-Cache'], 'miss')
        self.assertEqual(len(self.engine.calls), 5)

    def test_vorbis_is_cached_separately_and_served_with_its_content_type(self):
        import soundfile
        import numpy
        output = io.BytesIO()
        soundfile.write(output, numpy.zeros(2400), 24000, format='OGG', subtype='VORBIS')
        ogg = output.getvalue()
        def synthesize(text, voice, speed, cancel_event=None, audio_format='wav'):
            self.engine.calls.append((text, voice, speed, audio_format))
            return ogg if audio_format == 'ogg' else self.audio
        self.engine.synthesize = synthesize
        self.assertEqual(self.speak()[2]['Content-Type'], 'audio/wav')
        first = self.speak(format='ogg', request_id='ogg-first')
        self.assertEqual(first[0], 200)
        self.assertEqual(first[2]['Content-Type'], 'audio/ogg')
        self.assertTrue(first[1].startswith(b'OggS'))
        self.assertEqual(self.speak(format='ogg')[2]['X-Speech-Cache'], 'hit')
        self.assertEqual(len(self.engine.calls), 2)
        self.assertEqual(len(list(self.cache_dir.glob('*.ogg'))), 1)
        self.assertEqual(self.speak(format='mp3')[0], 400)

    def test_cache_is_bounded_and_corruption_regenerates(self):
        self.stop_server(); self.start_server(limit=130)
        self.speak('First.'); self.speak('Second.'); self.speak('First.'); self.speak('Third.')
        files = list(self.cache_dir.glob('*.wav'))
        self.assertLessEqual(sum(p.stat().st_size for p in files), 130)
        self.assertEqual(self.speak('Second.')[2]['X-Speech-Cache'], 'miss')
        for file in self.cache_dir.glob('*.wav'):
            file.write_bytes(b'corrupt')
        self.assertEqual(self.speak('Second.')[1], self.audio)
        self.assertEqual(len(self.engine.calls), 5)

    def test_cache_cleanup_failure_does_not_discard_generated_audio(self):
        with patch.object(Path, 'unlink', side_effect=PermissionError('Fixture cache inaccessible')):
            result = self.speak(request_id='cache-unavailable')
        self.assertEqual(result[0], 200)
        self.assertEqual(result[1], self.audio)

    def test_cancel_before_arrival_prevents_generation_without_touching_other_requests(self):
        response = self.request('/v1/speech/cancel', {'request_id':'obsolete'})
        self.assertEqual(response[0], 200)
        rejected = self.speak(request_id='obsolete')
        self.assertEqual(rejected[0], 409)
        self.assertEqual(json.loads(rejected[1])['code'], 'cancelled')
        self.assertEqual(self.engine.calls, [])
        self.assertEqual(self.speak(request_id='current')[0], 200)
        self.assertEqual(self.request('/v1/speech/cancel', {'request_id':'../../bad'})[0], 400)

    def test_inflight_cancel_discards_audio_and_no_stale_work_is_queued(self):
        entered, release = threading.Event(), threading.Event()
        result = []
        def blocked(text, voice, speed, cancel_event=None):
            self.engine.calls.append((text, voice, speed))
            entered.set()
            if not release.wait(2): raise TimeoutError('Fixture not released')
            self.assertTrue(cancel_event.is_set())
            return self.audio
        self.engine.synthesize = blocked
        pending = threading.Thread(target=lambda: result.append(self.speak(request_id='old')))
        pending.start()
        try:
            self.assertTrue(entered.wait(1))
            self.assertTrue(json.loads(self.request('/v1/speech/cancel', {'request_id':'old'})[1])['active'])
            busy = self.speak('New line.', request_id='new')
            self.assertEqual(busy[0], 409)
            self.assertEqual(json.loads(busy[1])['code'], 'busy')
            self.assertEqual(len(self.engine.calls), 1)
        finally:
            release.set(); pending.join(2)
        self.assertEqual(result[0][0], 409)
        self.assertEqual(json.loads(result[0][1])['code'], 'cancelled')
        self.assertEqual(list(self.cache_dir.glob('*.wav')), [])

    def test_cache_hit_does_not_wait_for_obsolete_inference(self):
        self.speak('Repeated line.')
        entered, release = threading.Event(), threading.Event()
        def blocked(text, voice, speed, cancel_event=None):
            entered.set()
            if not release.wait(2): raise TimeoutError('Fixture not released')
            return self.audio
        self.engine.synthesize = blocked
        pending = threading.Thread(target=lambda: self.speak('Slow line.', request_id='old'))
        pending.start()
        try:
            self.assertTrue(entered.wait(1))
            self.request('/v1/speech/cancel', {'request_id':'old'})
            self.assertEqual(self.speak('Repeated line.', request_id='new')[2]['X-Speech-Cache'], 'hit')
        finally:
            release.set(); pending.join(2)


if __name__ == '__main__':
    unittest.main()
