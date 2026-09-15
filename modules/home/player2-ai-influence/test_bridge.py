"""Boundary regression checks with a fake upstream; consume no Player2 credits."""
import contextlib
import http.client
import http.server
import importlib.util
import io
import json
import threading
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('bridge', Path(__file__).with_name('bridge.py'))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class Upstream(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        self.do_POST()

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.server.requests.append((self.path, self.headers.get('Authorization'), body))
        status, payload, content_type = self.server.reply
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


class BridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.upstream = http.server.HTTPServer(('127.0.0.1', 0), Upstream)
        cls.upstream.requests = []
        cls.local = bridge.Bridge(('127.0.0.1', 0), 'test-private-key',
                                  'http://127.0.0.1:' + str(cls.upstream.server_port))
        cls.threads = []
        for server in (cls.upstream, cls.local):
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            cls.threads.append(thread)

    @classmethod
    def tearDownClass(cls):
        for server in (cls.local, cls.upstream):
            server.shutdown()
            server.server_close()
        for thread in cls.threads:
            thread.join()

    def setUp(self):
        self.upstream.requests.clear()
        self.upstream.reply = (200, b'{}', 'application/json')

    def call(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.local.server_port, timeout=5)
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        result = response.status, response.read()
        connection.close()
        return result

    def test_chat_preserves_request_response_and_keeps_key_upstream(self):
        body = b'{"messages":[{"role":"user","content":"Test"}],"stream":false}'
        self.upstream.reply = (200, b'{"choices":[{"message":{"content":"hello"}}]}', 'application/json')
        status, result = self.call('POST', '/v1/chat/completions', body, {'Content-Type': 'application/json'})
        self.assertEqual((status, result), self.upstream.reply[:2])
        self.assertEqual(self.upstream.requests, [('/v1/chat/completions', 'Bearer test-private-key', body)])
        self.assertNotIn(b'test-private-key', result)

    def test_preserves_insufficient_credit_and_rate_limit_errors(self):
        for status in (401, 402, 429, 500):
            with self.subTest(status=status):
                self.upstream.reply = (status, b'{"error":"provider error"}', 'application/json')
                self.assertEqual(self.call('GET', '/v1/health'), self.upstream.reply[:2])

    def test_stream_is_unmodified(self):
        self.upstream.reply = (200, b'data: {"choices":[]}\n\ndata: [DONE]\n\n', 'text/event-stream')
        self.assertEqual(self.call('POST', '/v1/chat/completions', b'{"messages":[],"stream":true}',
                                   {'Content-Type': 'application/json'}), self.upstream.reply[:2])

    def test_health_identifies_bridge_only_after_valid_upstream_success(self):
        status, result = self.call('GET', '/v1/health')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(result)['client_version'], 'player2-web-bridge/0.1')
        self.upstream.reply = (200, b'not json', 'text/plain')
        self.assertEqual(self.call('GET', '/v1/health')[0], 502)

    def test_browser_origin_and_rebinding_host_never_reach_upstream(self):
        for headers in ({'Origin': 'https://unrelated.example'}, {'Host': 'unrelated.example'}):
            self.assertEqual(self.call('GET', '/v1/health', headers=headers)[0], 403)
        self.assertEqual(self.upstream.requests, [])

    def test_no_auth_key_export_or_remote_mic_emulation(self):
        for path in ('/v1/login/web/' + bridge.CLIENT_ID, '/v1/stt/start'):
            self.assertEqual(self.call('POST', path, b'{}', {'Content-Type': 'application/json'})[0], 501)
        self.assertEqual(self.call('POST', '/v1/tts/speak', b'{"play_in_app":true}',
                                   {'Content-Type': 'application/json'})[0], 501)
        self.assertEqual(self.upstream.requests, [])

    def test_bad_and_excessive_body_never_reaches_upstream(self):
        self.assertEqual(self.call('POST', '/v1/chat/completions', b'not json', {'Content-Type': 'application/json'})[0], 400)
        self.assertEqual(self.call('POST', '/v1/chat/completions', b'{}',
                                   {'Content-Type': 'application/json', 'Content-Length': str(bridge.MAX_BODY + 1)})[0], 413)
        self.assertEqual(self.upstream.requests, [])


if __name__ == '__main__':
    unittest.main()
