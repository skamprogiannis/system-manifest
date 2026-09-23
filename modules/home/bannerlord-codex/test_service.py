"""Service glue tests use fake CLI/status results and an in-process HTTP server."""
from contextlib import redirect_stdout, redirect_stderr
import io
import json
import subprocess
import threading
import unittest
from unittest.mock import patch

import adapter
import control
import preflight


class ServiceGlue(unittest.TestCase):
    def result(self, text, code=0):
        return subprocess.CompletedProcess([], code, text)

    def test_preflight_accepts_expected_cli_and_chatgpt(self):
        with patch.object(preflight.subprocess, "run", side_effect=[
            self.result("codex-cli 0.156.1\n"), self.result("Logged in using ChatGPT\n")
        ]) as run:
            preflight.check()
        self.assertEqual([c.args[0] for c in run.call_args_list],
                         [["codex", "--version"], ["codex", "login", "status"]])
        for call in run.call_args_list:
            self.assertNotIn("OPENAI_API_KEY", call.kwargs["env"])

    def test_preflight_rejects_changed_cli_without_auth_query(self):
        with patch.object(preflight.subprocess, "run", return_value=self.result("codex-cli 1.0")) as run:
            with self.assertRaises(preflight.PreflightError):
                preflight.check()
        self.assertEqual(run.call_count, 1)

    def test_preflight_never_exposes_login_output(self):
        with patch.object(preflight.subprocess, "run", side_effect=[
            self.result("codex-cli 0.156.1"), self.result("Logged in using an API key PRIVATE-CANARY")
        ]):
            with self.assertRaises(preflight.PreflightError) as caught:
                preflight.check()
        self.assertNotIn("PRIVATE-CANARY", str(caught.exception))

    def test_health_and_status_use_no_generation(self):
        def forbidden(*args, **kwargs):
            self.fail("Readiness must never send a generation request")
        server = adapter.serve(0, generator=forbidden)
        thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02})
        thread.start()
        try:
            data = control.health("http://127.0.0.1:%d/healthz" % server.server_port)
        finally:
            server.shutdown()
            thread.join()
            server.server_close()
        self.assertTrue(data["adapter_ready"])
        output = io.StringIO()
        with patch.object(control, "active", return_value=True), patch.object(control, "health", return_value=data), redirect_stdout(output):
            self.assertEqual(control.main(["status"]), 0)
        self.assertIn("quota are not verified", output.getvalue())

    def test_health_rejects_malformed_or_unrelated_responses(self):
        for data in (None, [], "ready", {"status": "ready"}):
            with self.subTest(data=data), patch.object(control.urllib.request, "build_opener") as build:
                response = build.return_value.open.return_value.__enter__.return_value
                response.status = 200
                response.read.return_value = json.dumps(data).encode()
                self.assertIsNone(control.health())

    def test_stop_targets_whole_named_user_unit(self):
        with patch.object(control.subprocess, "run", return_value=self.result("")) as run, redirect_stdout(io.StringIO()):
            self.assertEqual(control.main(["stop"]), 0)
        self.assertEqual(run.call_args.args[0], ["systemctl", "--user", "stop", "bannerlord-codex.service"])

    def test_start_requires_unit_and_health_readiness(self):
        data = {"adapter_ready": True, "model": "gpt-5.6-sol", "account_and_quota_verified": False}
        with patch.object(control.subprocess, "run", return_value=self.result("")) as run, patch.object(control, "active", return_value=True), patch.object(control, "health", return_value=data), redirect_stdout(io.StringIO()):
            self.assertEqual(control.main(["start"]), 0)
        self.assertEqual(run.call_args.args[0], ["systemctl", "--user", "start", "bannerlord-codex.service"])

    def test_inactive_status_and_invalid_usage_fail_clearly(self):
        with patch.object(control, "active", return_value=False), redirect_stdout(io.StringIO()):
            self.assertEqual(control.main(["status"]), 3)
        with redirect_stderr(io.StringIO()):
            self.assertEqual(control.main(["start", "extra"]), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
