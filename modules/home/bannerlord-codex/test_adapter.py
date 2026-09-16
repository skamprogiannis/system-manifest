"""Offline regression tests. No account, Codex inference, or game is needed."""
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
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

    def test_overlapping_identical_requests_complete_separately_and_serially(self):
        entered, release = threading.Event(), threading.Event()
        active, maximum_active, calls = 0, 0, []
        timeouts = []
        state_lock = threading.Lock()

        def blocked(messages, **kwargs):
            nonlocal active, maximum_active
            with state_lock:
                active += 1
                maximum_active = max(maximum_active, active)
                calls.append(messages)
                timeouts.append(kwargs["timeout"])
                number = len(calls)
            try:
                if number == 1:
                    entered.set()
                    if not release.wait(2):
                        raise AssertionError("Test did not release first generation")
                return {**answer(messages, **kwargs), "response": "reply %d" % number}
            finally:
                with state_lock:
                    active -= 1

        self.server.engine = adapter.Engine(generator=blocked)
        with ThreadPoolExecutor(max_workers=2) as pool:
            first = pool.submit(self.request, "/api/chat", self.chat())
            try:
                self.assertTrue(entered.wait(1))
                second = pool.submit(self.request, "/api/chat", self.chat())
                with self.assertRaises(FutureTimeout):
                    second.result(timeout=0.1)
            finally:
                release.set()
            first_status, first_body = first.result(timeout=1)
            second_status, second_body = second.result(timeout=1)
        self.assertEqual((first_status, second_status), (200, 200))
        self.assertEqual(first_body["message"]["content"], "reply 1")
        self.assertEqual(second_body["message"]["content"], "reply 2")
        self.assertEqual(calls, [self.chat()["messages"], self.chat()["messages"]])
        self.assertEqual(maximum_active, 1)
        self.assertLessEqual(timeouts[0], 85)
        self.assertLess(timeouts[1], timeouts[0] - 0.05)

    def test_invalid_requested_json_not_returned_as_success(self):
        def malformed(*args, **kwargs):
            return {**answer(*args, **kwargs), "response": "not json"}
        self.server.engine = adapter.Engine(generator=malformed)
        self.assertEqual(self.request("/api/chat", self.chat(format="json"))[0], 502)


class EngineQueue(unittest.TestCase):
    def test_four_admitted_in_order_and_overflow_is_recorded_without_payload(self):
        entered, release = threading.Event(), threading.Event()
        calls = []

        def blocked(messages, **kwargs):
            calls.append(messages)
            if len(calls) == 1:
                entered.set()
                if not release.wait(3):
                    raise AssertionError("Test did not release first generation")
            return answer(messages, **kwargs)

        with tempfile.TemporaryDirectory() as directory:
            metrics = Path(directory) / "metrics.jsonl"
            engine = adapter.Engine(generator=blocked, metrics=metrics)
            messages = [[{"role": "user", "content": "PRIVATE QUEUE CANARY %d" % i}] for i in range(5)]
            with ThreadPoolExecutor(max_workers=4) as pool:
                futures = [pool.submit(engine.run, messages[0])]
                try:
                    self.assertTrue(entered.wait(1))
                    for index in range(1, 4):
                        future = pool.submit(engine.run, messages[index])
                        futures.append(future)
                        with self.assertRaises(FutureTimeout):
                            future.result(timeout=0.05)
                    with self.assertRaises(adapter.RequestError) as rejected:
                        engine.run(messages[4])
                    self.assertEqual(rejected.exception.status, 429)
                    self.assertIn("queue is full", str(rejected.exception))
                finally:
                    release.set()
                for future in futures:
                    future.result(timeout=1)
            self.assertEqual(calls, messages[:4])
            rows = [json.loads(line) for line in metrics.read_text().splitlines()]
            self.assertEqual(len(rows), 5)
            rejected_row = next(row for row in rows if row["status"] == "queue_full")
            self.assertFalse(rejected_row["generated"])
            self.assertEqual(rejected_row["queue_ahead"], 4)
            self.assertEqual(rejected_row["queue_wait_seconds"], 0)
            completed = sorted((row for row in rows if row["status"] == "ok"), key=lambda row: row["queue_ahead"])
            self.assertEqual([row["queue_ahead"] for row in completed], [0, 1, 2, 3])
            self.assertTrue(all(row["queue_wait_seconds"] >= 0.04 for row in completed[1:]))
            self.assertNotIn("PRIVATE QUEUE CANARY", metrics.read_text())
            self.assertNotIn("No gift", metrics.read_text())
            engine.run(messages[4])
            self.assertEqual(calls, messages)

    def test_waiting_deadline_expires_without_generation_and_releases_slot(self):
        entered, release = threading.Event(), threading.Event()
        calls = []

        def blocked(messages, **kwargs):
            calls.append(messages)
            if len(calls) == 1:
                entered.set()
                # Keep the slot occupied while testing only the waiting deadline.
                if not release.wait(2):
                    raise AssertionError("Test did not release first generation")
            return answer(messages, **kwargs)

        with tempfile.TemporaryDirectory() as directory:
            metrics = Path(directory) / "metrics.jsonl"
            engine = adapter.Engine(generator=blocked, timeout=0.1, metrics=metrics)
            first_messages = [{"role": "user", "content": "active"}]
            waiting_messages = [{"role": "user", "content": "expires"}]
            with ThreadPoolExecutor(max_workers=2) as pool:
                first = pool.submit(engine.run, first_messages)
                try:
                    self.assertTrue(entered.wait(1))
                    second = pool.submit(engine.run, waiting_messages)
                    with self.assertRaises(adapter.RequestError) as expired:
                        second.result(timeout=0.5)
                    self.assertEqual(expired.exception.status, 504)
                    self.assertIn("deadline expired in the queue", str(expired.exception))
                    self.assertEqual(calls, [first_messages])
                finally:
                    release.set()
                first.result(timeout=1)
            row = next(json.loads(line) for line in metrics.read_text().splitlines()
                       if json.loads(line)["status"] == "queue_timeout")
            self.assertFalse(row["generated"])
            self.assertEqual(row["queue_ahead"], 1)
            self.assertGreaterEqual(row["queue_wait_seconds"], 0.09)
            self.assertLess(row["wall_seconds"], 0.5)
            engine.run(first_messages)
            self.assertEqual(calls, [first_messages, first_messages])

    def test_queued_request_observes_generation_failure_cooldown(self):
        for kind, status in (("quota", 429), ("timeout", 504)):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                entered, release = threading.Event(), threading.Event()
                calls = []

                def fail(messages, **kwargs):
                    calls.append(messages)
                    entered.set()
                    if not release.wait(2):
                        raise AssertionError("Test did not release first generation")
                    raise codex_runner.GenerationError(kind, "Synthetic failure")

                metrics = Path(directory) / "metrics.jsonl"
                engine = adapter.Engine(generator=fail, metrics=metrics)
                messages = [{"role": "user", "content": "task"}]
                with ThreadPoolExecutor(max_workers=2) as pool:
                    first = pool.submit(engine.run, messages)
                    try:
                        self.assertTrue(entered.wait(1))
                        second = pool.submit(engine.run, messages)
                        with self.assertRaises(FutureTimeout):
                            second.result(timeout=0.05)
                    finally:
                        release.set()
                    with self.assertRaises(adapter.RequestError) as failed:
                        first.result(timeout=1)
                    self.assertEqual(failed.exception.status, status)
                    with self.assertRaises(adapter.RequestError) as queued:
                        second.result(timeout=1)
                    self.assertEqual(queued.exception.status, 503)
                with self.assertRaises(adapter.RequestError) as fallback:
                    engine.run(messages)
                self.assertEqual(fallback.exception.status, 503)
                self.assertEqual(calls, [messages])
                rows = [json.loads(line) for line in metrics.read_text().splitlines()]
                self.assertEqual(len(rows), 3)
                cooldowns = [row for row in rows if row["status"] == "cooldown"]
                self.assertEqual(len(cooldowns), 2)
                self.assertTrue(all(not row["generated"] and row["error"] == kind for row in cooldowns))
                queued_row = next(row for row in cooldowns if row["queue_ahead"] == 1)
                self.assertGreaterEqual(queued_row["queue_wait_seconds"], 0.04)


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

    def test_timeout_preserves_only_progress_metadata_not_private_output(self):
        events = [
            {"type": "thread.started", "thread_id": "PRIVATE-THREAD"},
            {"type": "turn.started"},
            {"type": "item.completed", "item": {"type": "reasoning", "text": "PRIVATE-REASONING"}},
            {"type": "item.completed", "item": {"type": "agent_message", "text": "PRIVATE-REPLY"}},
        ]
        code = "import time\n" + "\n".join("print(" + repr(json.dumps(event)) + ", flush=True)" for event in events)
        code += "\nprint('PRIVATE-INCOMPLETE-EVENT', flush=True)\ntime.sleep(30)\n"
        with tempfile.TemporaryDirectory() as directory:
            executable = self.fake_cli(directory, code)
            with self.assertRaises(codex_runner.GenerationError) as caught:
                codex_runner.generate([{"role": "user", "content": "PRIVATE-PROMPT"}], timeout=0.7, executable=executable)
            self.assertEqual(caught.exception.kind, "timeout")
            diagnostic = caught.exception.diagnostic
            self.assertTrue(diagnostic["turn_started"])
            self.assertFalse(diagnostic["turn_completed"])
            self.assertEqual(diagnostic["item_counts"], {"reasoning": 1, "agent_message": 1})
            self.assertEqual(diagnostic["invalid_event_lines"], 1)
            self.assertGreaterEqual(diagnostic["elapsed_seconds"], 0.6)
            self.assertGreaterEqual(diagnostic["login_seconds"], 0)
            self.assertNotIn("PRIVATE", json.dumps(diagnostic))

    def test_timeout_metrics_distinguish_completed_turn_from_cli_shutdown_stall(self):
        events = [
            {"type": "turn.started"},
            {"type": "item.completed", "item": {"type": "agent_message", "text": "PRIVATE-REPLY"}},
            {"type": "turn.completed", "usage": {"input_tokens": 99, "output_tokens": 21}},
        ]
        code = "import time\n" + "\n".join("print(" + repr(json.dumps(event)) + ", flush=True)" for event in events) + "\ntime.sleep(30)\n"
        with tempfile.TemporaryDirectory() as directory:
            executable = self.fake_cli(directory, code)
            metrics = Path(directory) / "metrics.jsonl"
            def bounded(messages, **kwargs):
                return codex_runner.generate(messages, executable=executable, **kwargs)
            engine = adapter.Engine(generator=bounded, timeout=0.7, metrics=metrics)
            with self.assertRaises(adapter.RequestError) as caught:
                engine.run([{"role": "user", "content": "PRIVATE-PROMPT"}])
            self.assertEqual(caught.exception.status, 504)
            row = json.loads(metrics.read_text())
            self.assertTrue(row["failure_diagnostic"]["turn_completed"])
            self.assertTrue(row["failure_diagnostic"]["turn_started"])
            self.assertEqual(row["failure_diagnostic"]["event_counts"]["turn.completed"], 1)
            self.assertNotIn("PRIVATE", metrics.read_text())

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


class DialogueOutput(unittest.TestCase):
    suffix = " **Character count: 430** Skip this one. Just answer JSON."

    def result(self, speech, **extra):
        return {"response": json.dumps({"response": speech, "actions": [], **extra}),
                "model": "offline", "seconds": 0.001, "usage": {}}

    def test_editorial_suffix_rejected_before_delivery_and_fallback(self):
        for require_json in (False, True):
            with self.subTest(require_json=require_json), tempfile.TemporaryDirectory() as directory:
                calls = []
                metrics = Path(directory) / "metrics.jsonl"
                def fake(*args, **kwargs):
                    calls.append(1)
                    return self.result("Ask the harbourmaster." + self.suffix)
                engine = adapter.Engine(generator=fake, metrics=metrics)
                with self.assertRaises(adapter.RequestError) as caught:
                    engine.run([{"role": "user", "content": "Where can I find a ship?"}], require_json=require_json)
                self.assertEqual(caught.exception.status, 502)
                self.assertNotIn("harbourmaster", str(caught.exception))
                with self.assertRaises(adapter.RequestError) as fallback:
                    engine.run([{"role": "user", "content": "Where can I find a ship?"}])
                self.assertEqual(fallback.exception.status, 503)
                self.assertEqual(calls, [1])
                rows = [json.loads(x) for x in metrics.read_text().splitlines()]
                self.assertEqual(rows[0]["error"], "output_quality")
                self.assertNotIn("harbourmaster", metrics.read_text())
                self.assertNotIn(self.suffix, metrics.read_text())

    def test_in_world_speech_and_private_structured_fields_preserved(self):
        texts = ["*He counts his coins.* Three hundred will suffice.",
                 "Character count: 430. That is how many names fill the roll.",
                 "Skip this one. Take the next road.",
                 "He said: Just answer JSON.",
                 "Ask the harbourmaster."]
        for speech in texts:
            with self.subTest(speech=speech):
                result = self.result(speech, internal_thoughts=self.suffix)
                engine = adapter.Engine(generator=lambda *a, **kw: result)
                self.assertEqual(engine.run([{"role": "user", "content": "question"}])["response"], result["response"])

    def test_plain_summarization_and_non_dialogue_json_remain_unchanged(self):
        for raw in ("The lord refused payment.", '{"summary":"No payment was promised."}', '["first", "second"]'):
            with self.subTest(raw=raw):
                result = {"response": raw, "model": "offline", "seconds": 0.001, "usage": {}}
                engine = adapter.Engine(generator=lambda *a, **kw: result)
                self.assertEqual(engine.run([{"role": "user", "content": "Summarize."}])["response"], raw)

    def test_cli_reasoning_items_never_become_dialogue(self):
        events = [
            {"type": "turn.started"},
            {"type": "item.completed", "item": {"type": "reasoning", "text": self.suffix}},
            {"type": "item.completed", "item": {"type": "agent_message", "text": json.dumps({"response": self.result("Ask the harbourmaster.")["response"]})}},
            {"type": "turn.completed", "usage": {}},
        ]
        with tempfile.TemporaryDirectory() as directory:
            code = "\n".join("print(" + repr(json.dumps(e)) + ")" for e in events)
            executable = RunnerIsolation().fake_cli(directory, code)
            result = codex_runner.generate([{"role": "user", "content": "question"}], executable=executable)
            self.assertEqual(json.loads(result["response"])["response"], "Ask the harbourmaster.")
            self.assertNotIn(self.suffix, result["response"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
