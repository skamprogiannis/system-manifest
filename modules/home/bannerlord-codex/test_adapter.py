"""Offline regression tests. No account, Codex inference, or game is needed."""
import http.client
import json
import os
import sys
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import adapter
import codex_runner


def answer(messages, **options):
    return {"response": '{"response":"No gift has been agreed.","actions":[]}', "model": options.get("model"),
            "seconds": 0.01, "usage": {"input_tokens": 200, "output_tokens": 15}}


class HttpContract(unittest.TestCase):
    def setUp(self):
        self.calls = []
        def fake(messages, **kwargs):
            self.calls.append(messages)
            return answer(messages, **kwargs)
        self.server = adapter.serve(0, generator=fake)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.02})
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()

    def request(self, path, body=None, headers=None, method="POST"):
        client = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        try:
            encoded = json.dumps(body).encode() if body is not None else None
            client.request(method, path, body=encoded, headers={"Content-Type": "application/json", **(headers or {})})
            response = client.getresponse()
            return response.status, json.loads(response.read())
        finally:
            client.close()

    def chat(self, **extra):
        return {"model": adapter.ALIAS, "stream": False, "messages": [
            {"role": "system", "content": "Task A"}, {"role": "user", "content": "NPC A"}], **extra}

    def test_actual_chat_envelope_and_request_boundary(self):
        status, body = self.request("/api/chat", self.chat(options={"temperature": 0.7, "top_p": 0.9}))
        self.assertEqual(status, 200)
        self.assertTrue(body["done"])
        self.assertEqual(json.loads(body["message"]["content"])["actions"], [])
        self.request("/api/chat", self.chat(messages=[{"role": "user", "content": "NPC B"}]))
        self.assertEqual(self.calls[1], [{"role": "user", "content": "NPC B"}])
        self.assertEqual(len(self.calls), 2)

    def test_generate_envelope(self):
        status, body = self.request("/api/generate", {"model": adapter.ALIAS, "stream": False, "prompt": "Summarize"})
        self.assertEqual(status, 200)
        self.assertIn("response", body)
        self.assertNotIn("message", body)

    def test_browser_and_rebinding_rejected_before_generation(self):
        for headers in ({"Origin": "https://example.com"}, {"Sec-Fetch-Site": "cross-site"}, {"Host": "attacker.invalid"}):
            with self.subTest(headers=headers):
                self.assertEqual(self.request("/api/chat", self.chat(), headers)[0], 403)
        self.assertEqual(self.calls, [])

    def test_non_text_streaming_unknown_models_and_options_rejected(self):
        cases = [self.chat(stream=True), self.chat(model="some-other-model"), self.chat(tools=[]),
                 self.chat(messages=[{"role": "user", "content": "x", "images": ["data"]}]),
                 self.chat(options={"num_gpu": 50}), self.chat(options={"temperature": float("nan")})]
        for body in cases:
            with self.subTest(body=body):
                self.assertGreaterEqual(self.request("/api/chat", body)[0], 400)
        self.assertEqual(self.calls, [])

    def test_oversized_prompt_and_body_rejected(self):
        self.assertEqual(self.request("/api/chat", self.chat(messages=[{"role": "user", "content": "x" * (adapter.MAX_TEXT + 1)}]))[0], 413)
        # Reject on declared length, before transmitting an oversized body. A
        # real uploader can see a broken pipe once the server closes early.
        self.assertEqual(self.request("/api/generate", headers={"Content-Length": str(adapter.MAX_BODY + 1)})[0], 413)
        self.assertEqual(self.calls, [])

    def test_health_does_not_claim_account_or_consume_inference(self):
        status, body = self.request("/healthz", method="GET")
        self.assertEqual(status, 200)
        self.assertFalse(body["account_and_quota_verified"])
        self.assertEqual(self.request("/api/version", method="GET")[0], 200)
        self.assertEqual(self.calls, [])

    def test_error_blocks_mod_fallback_generation(self):
        for kind in ("quota", "timeout"):
            with self.subTest(kind=kind):
                calls = []
                def fail(*args, **kwargs):
                    calls.append(1)
                    raise codex_runner.GenerationError(kind, "Synthetic failure")
                self.server.engine = adapter.Engine(generator=fail)
                self.assertIn(self.request("/api/chat", self.chat())[0], (429, 504))
                status, body = self.request("/api/generate", {"model": adapter.ALIAS, "stream": False, "prompt": "same task"})
                self.assertEqual(status, 503)
                self.assertIn("cooldown", body["error"])
                self.assertEqual(len(calls), 1)

    def test_busy_rejected_and_lock_released(self):
        self.server.engine.lock.acquire()
        try:
            self.assertEqual(self.request("/api/chat", self.chat())[0], 429)
        finally:
            self.server.engine.lock.release()
        self.assertEqual(self.request("/api/chat", self.chat())[0], 200)
        self.assertEqual(len(self.calls), 1)

    def test_invalid_requested_json_not_returned_as_success(self):
        def malformed(*args, **kwargs):
            return {**answer(*args, **kwargs), "response": "not json"}
        self.server.engine = adapter.Engine(generator=malformed)
        self.assertEqual(self.request("/api/chat", self.chat(format="json"))[0], 502)


class RunnerIsolation(unittest.TestCase):
    def test_no_user_config_tools_or_reused_conversation(self):
        args = codex_runner.command("model", "/tmp/isolated")
        for arg in ("--ignore-user-config", "--strict-config", "--ephemeral", "--output-schema", "read-only"):
            self.assertIn(arg, args)
        for setting in ("features.code_mode=false", "features.shell_tool=false", "features.multi_agent=false", "project_doc_max_bytes=0"):
            self.assertIn(setting, args)
        self.assertNotIn("resume", args)
        self.assertNotIn("--dangerously-bypass-approvals-and-sandbox", args)

    def test_api_keys_and_parent_control_state_not_inherited(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "dummy", "CODEX_API_KEY": "dummy", "CODEX_HOME": "/dummy", "OPENAI_BASE_URL": "https://dummy.invalid"}):
            env = codex_runner.environment()
        for key in ("OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_HOME", "OPENAI_BASE_URL"):
            self.assertNotIn(key, env)

    def fake_cli(self, directory, code):
        path = Path(directory) / "fake-codex"
        login = "import sys\nif sys.argv[1:]==['login','status']:\n print('Logged in using ChatGPT')\n sys.exit(0)\n"
        path.write_text("#!" + sys.executable + "\n" + login + code)
        path.chmod(0o700)
        return str(path)

    def test_deadline_terminates_process(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = self.fake_cli(directory, "import time\ntime.sleep(30)\n")
            start = time.monotonic()
            with self.assertRaises(codex_runner.GenerationError) as caught:
                codex_runner.generate([{"role": "user", "content": "x"}], timeout=0.1, executable=executable)
            self.assertEqual(caught.exception.kind, "timeout")
            self.assertLess(time.monotonic() - start, 4)

    def test_saved_api_key_login_is_rejected_without_inference(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fake-codex"
            path.write_text("#!" + sys.executable + "\nimport sys\nassert sys.argv[1:]==['login','status']\nprint('Logged in using an API key')\n")
            path.chmod(0o700)
            with self.assertRaises(codex_runner.GenerationError) as caught:
                codex_runner.generate([{"role": "user", "content": "x"}], executable=str(path))
            self.assertEqual(caught.exception.kind, "auth")

    def test_cli_envelope_and_fresh_directory(self):
        code = '''import json,os,sys
data=json.load(sys.stdin)
result={"response":json.dumps({"cwd":os.getcwd(),"messages":data["messages"]})}
print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":json.dumps(result)}}))
print(json.dumps({"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":10}}))
'''
        with tempfile.TemporaryDirectory() as directory:
            executable = self.fake_cli(directory, code)
            a = codex_runner.generate([{"role": "user", "content": "A"}], executable=executable)
            b = codex_runner.generate([{"role": "user", "content": "B"}], executable=executable)
            a, b = json.loads(a["response"]), json.loads(b["response"])
            self.assertNotEqual(a["cwd"], b["cwd"])
            self.assertFalse(Path(a["cwd"]).exists())
            self.assertEqual(b["messages"], [{"role": "user", "content": "B"}])

    def test_tool_attempt_and_startup_error_fail_closed(self):
        for item_type in ("command_execution", "error"):
            with self.subTest(item_type=item_type), tempfile.TemporaryDirectory() as directory:
                event = {"type": "item.completed", "item": {"type": item_type}}
                executable = self.fake_cli(directory, "print(" + repr(json.dumps(event)) + ")\n")
                with self.assertRaises(codex_runner.GenerationError) as caught:
                    codex_runner.generate([{"role": "user", "content": "x"}], executable=executable)
                self.assertEqual(caught.exception.kind, "unexpected_item")

    def test_metrics_contain_no_prompts_or_responses(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "metrics.jsonl"
            adapter.Engine(metrics=path, generator=answer).run([{"role": "user", "content": "PRIVATE TEST CANARY"}])
            text = path.read_text()
            self.assertNotIn("PRIVATE TEST CANARY", text)
            self.assertNotIn("No gift", text)
            self.assertIn("input_tokens", text)

    def test_only_exact_disabled_host_notice_before_turn_is_accepted(self):
        notice = {"type": "item.completed", "item": {"type": "error", "message": codex_runner.DISABLED_CODE_HOST_NOTICE}}
        turn = {"type": "turn.started"}
        final = {"type": "item.completed", "item": {"type": "agent_message", "text": '{"response":"ok"}'}}
        complete = {"type": "turn.completed", "usage": {}}
        with tempfile.TemporaryDirectory() as directory:
            executable = self.fake_cli(directory, "\n".join("print(" + repr(json.dumps(e)) + ")" for e in [notice, turn, final, complete]))
            result = codex_runner.generate([{"role": "user", "content": "x"}], executable=executable)
            self.assertEqual(result["warnings"], ["coding_host_intentionally_disabled"])
            executable = self.fake_cli(directory, "\n".join("print(" + repr(json.dumps(e)) + ")" for e in [turn, notice, final, complete]))
            with self.assertRaises(codex_runner.GenerationError):
                codex_runner.generate([{"role": "user", "content": "x"}], executable=executable)


if __name__ == "__main__":
    unittest.main(verbosity=2)
