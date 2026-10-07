"""Run the bootstrap supervisor against real child processes and terminal FDs."""

import io
import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import tempfile
import threading
import types
import time
import unittest
from unittest.mock import patch

SOURCE = Path(sys.argv.pop(1)).resolve()
TIMEOUT = "Error: account/read failed during TUI bootstrap: account/read failed: workspace routing discovery timed out (code -32603)"


class StartupTests(unittest.TestCase):
    def exercise(self, mode, error=TIMEOUT, interrupt=None):
        with tempfile.TemporaryDirectory(prefix="codex-startup-test-") as directory:
            root = Path(directory)
            fake = root / "native.py"
            fake.write_text("""import json, os, pathlib, signal, sys, time
root=pathlib.Path(os.environ['FIXTURE_ROOT']); count=root/'count'
n=int(count.read_text())+1 if count.exists() else 1; count.write_text(str(n))
(root/'observed.json').write_text(json.dumps({'args':sys.argv[1:],'enabled':os.environ['CODEX_CLEF_ENABLED'],'stdin_tty':sys.stdin.isatty(),'stdout_tty':sys.stdout.isatty()}))
mode=os.environ['FIXTURE_MODE']
if mode=='interrupt':
 (root/'ready').touch(); time.sleep(20)
if mode=='descendant':
 pid=os.fork()
 if pid==0:
  time.sleep(1); os._exit(0)
 sys.exit(0)
if mode=='retry' and n<3 or mode=='exhaust':
 print(os.environ['FIXTURE_ERROR'],file=sys.stderr);sys.exit(1)
if mode=='other':
 print(os.environ['FIXTURE_ERROR'],file=sys.stderr);sys.exit(1)
print('ANSI\\x1b[32moutput\\x1b[0m',flush=True)
print('KEY:'+sys.stdin.readline().strip(),flush=True)
""")
            runner = root / "runner.py"
            runner.write_text(
                'import os,sys\nsys.path.insert(0,sys.argv[1])\nfrom clef.startup import launch_interactive\nraise SystemExit(launch_interactive(sys.executable,[sys.executable,sys.argv[2],"--no-daemon","task"],dict(os.environ),backoff=0))\n'
            )
            env = dict(
                os.environ,
                FIXTURE_ROOT=str(root),
                FIXTURE_MODE=mode,
                FIXTURE_ERROR=error,
                CODEX_CLEF_ENABLED="1",
            )
            master, slave = pty.openpty()
            proc = subprocess.Popen(
                [sys.executable, str(runner), str(SOURCE), str(fake)],
                stdin=slave,
                stdout=slave,
                stderr=slave,
                env=env,
                start_new_session=True,
            )
            os.close(slave)
            output = bytearray()
            start = time.monotonic()
            try:
                if interrupt:
                    while (
                        not (root / "ready").exists()
                        and proc.poll() is None
                        and time.monotonic() - start < 5
                    ):
                        time.sleep(0.01)
                    os.kill(proc.pid, interrupt)
                else:
                    os.write(master, b"hello\n")
                while proc.poll() is None and time.monotonic() - start < 8:
                    if select.select([master], [], [], 0.05)[0]:
                        try:
                            output.extend(os.read(master, 65536))
                        except OSError:
                            break
                proc.wait(timeout=2)
                while select.select([master], [], [], 0.05)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError:
                        break
                self.assertTrue(
                    (root / "count").exists(), output.decode(errors="replace")
                )
                observed = json.loads((root / "observed.json").read_text())
                return (
                    proc.returncode,
                    int((root / "count").read_text()),
                    output.decode(errors="replace"),
                    observed,
                    time.monotonic() - start,
                )
            finally:
                if proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
                os.close(master)

    def test_exact_timeout_retries_twice_and_preserves_terminal_environment_arguments(
        self,
    ):
        status, count, output, observed, _ = self.exercise("retry")
        self.assertEqual((status, count), (0, 3))
        self.assertIn("KEY:hello", output)
        self.assertIn("\x1b[32moutput", output)
        self.assertEqual(observed["args"], ["--no-daemon", "task"])
        self.assertEqual(observed["enabled"], "1")
        self.assertTrue(observed["stdin_tty"])
        self.assertTrue(observed["stdout_tty"])
        self.assertEqual(output.count("retrying startup"), 2)

    def test_exhaustion_returns_original_failure(self):
        status, count, output, _, _ = self.exercise("exhaust")
        self.assertEqual((status, count), (1, 3))
        self.assertIn(TIMEOUT, output)

    def test_similar_or_runtime_errors_are_not_retried(self):
        for error in (
            TIMEOUT.replace("TUI bootstrap", "session runtime"),
            TIMEOUT.replace("-32603", "-32000"),
            "Error: workspace routing discovery timed out",
            TIMEOUT + " additional context",
            "Error: permission denied",
        ):
            with self.subTest(error=error):
                status, count, _, _, _ = self.exercise("other", error)
                self.assertEqual((status, count), (1, 1))

    def test_success_is_never_restarted(self):
        status, count, _, _, _ = self.exercise("success")
        self.assertEqual((status, count), (0, 1))

    def test_cancellation_preserves_signal_status_without_retry(self):
        for sig in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(sig=sig):
                status, count, _, _, _ = self.exercise("interrupt", interrupt=sig)
                self.assertEqual(status, 128 + sig)
                self.assertEqual(count, 1)

    def test_descendant_stderr_does_not_keep_launcher_alive(self):
        status, count, _, _, elapsed = self.exercise("descendant")
        self.assertEqual((status, count), (0, 1))
        self.assertLess(elapsed, 0.8)


class StartupFailureTests(unittest.TestCase):
    def setUp(self):
        sys.path.insert(0, str(SOURCE))
        from clef import startup

        self.startup = startup
        self.spawn = subprocess.Popen
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.kill()
            child.wait()
        sys.path.remove(str(SOURCE))

    def record_spawn(self, *args, **kwargs):
        child = self.spawn(*args, **kwargs)
        self.children.append(child)
        return child

    def test_signal_during_spawn_is_forwarded_before_relay(self):
        watchdog_fired = threading.Event()

        def spawn(*args, **kwargs):
            child = self.record_spawn(*args, **kwargs)
            os.kill(os.getpid(), signal.SIGTERM)
            return child

        def watchdog():
            watchdog_fired.set()
            for child in self.children:
                child.terminate()

        timer = threading.Timer(1, watchdog)
        timer.start()
        try:
            with patch.object(self.startup.subprocess, "Popen", side_effect=spawn):
                status = self.startup.launch_interactive(
                    sys.executable,
                    [sys.executable, "-c", "import time;time.sleep(20)"],
                    dict(os.environ),
                )
            self.assertEqual(status, 143)
            self.assertFalse(
                watchdog_fired.is_set(), "cancellation was lost during spawn"
            )
        finally:
            timer.cancel()
            timer.join()

    def test_relay_exceptions_terminate_and_reap_native_child(self):
        for boundary in ("setup", "select", "write"):
            with self.subTest(boundary=boundary):
                error = OSError("fixture relay failure")
                sink = types.SimpleNamespace(buffer=io.BytesIO())
                if boundary == "setup":
                    failing = patch.object(
                        self.startup.os, "set_blocking", side_effect=error
                    )
                elif boundary == "select":
                    failing = patch.object(
                        self.startup.select, "select", side_effect=error
                    )
                else:
                    sink.buffer = types.SimpleNamespace(
                        write=lambda _: (_ for _ in ()).throw(error)
                    )
                    failing = patch.object(self.startup.sys, "stderr", sink)
                with (
                    patch.object(
                        self.startup.subprocess, "Popen", side_effect=self.record_spawn
                    ),
                    failing,
                    self.assertRaisesRegex(OSError, "fixture relay failure"),
                ):
                    self.startup.launch_interactive(
                        sys.executable,
                        [
                            sys.executable,
                            "-c",
                            "import sys,time;sys.stderr.write('relay');sys.stderr.flush();time.sleep(20)",
                        ],
                        dict(os.environ),
                    )
                self.assertIsNotNone(
                    self.children[-1].poll(), "native child survived relay failure"
                )


if __name__ == "__main__":
    unittest.main()
