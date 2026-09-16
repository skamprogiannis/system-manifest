import http.client
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


if __name__ == '__main__':
    unittest.main()
