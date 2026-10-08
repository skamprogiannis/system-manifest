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
    def exercise(self, mode, error=TIMEOUT, interrupt=None, fallback=False, unsafe_daemon=False, ordinary=False):
        with tempfile.TemporaryDirectory(prefix="codex-startup-test-") as directory:
            root = Path(directory)
            fake = root / "native.py"
            fake.write_text("""import json, os, pathlib, signal, sys, time
root=pathlib.Path(os.environ['FIXTURE_ROOT']); count=root/'count'
n=int(count.read_text())+1 if count.exists() else 1; count.write_text(str(n))
(root/'observed.json').write_text(json.dumps({'args':sys.argv[1:],'enabled':os.environ['CODEX_CLEF_ENABLED'],'routing_mode':os.environ.get('CODEX_CLEF_ROUTING_MODE'),'stdin_tty':sys.stdin.isatty(),'stdout_tty':sys.stdout.isatty()}))
mode=os.environ['FIXTURE_MODE']
if mode=='interrupt':
 (root/'ready').touch(); time.sleep(20)
if mode=='descendant':
 pid=os.fork()
 if pid==0:
  time.sleep(1); os._exit(0)
 sys.exit(0)
if mode=='retry' and n<3 or mode=='exhaust' or mode=='fallback' and '--no-daemon' in sys.argv:
 print(os.environ['FIXTURE_ERROR'],file=sys.stderr);sys.exit(1)
if mode=='other':
 print(os.environ['FIXTURE_ERROR'],file=sys.stderr);sys.exit(1)
print('ANSI\\x1b[32moutput\\x1b[0m',flush=True)
print('KEY:'+sys.stdin.readline().strip(),flush=True)
""")
            runner = root / "runner.py"
            runner.write_text(
                'import os,sys\nsys.path.insert(0,sys.argv[1])\nfrom clef.startup import launch_interactive\n'
                'if os.environ["FIXTURE_UNSAFE_DAEMON"]=="1":\n'
                ' from clef import startup;startup._ordinary_daemon_safe=lambda _:False\n'
                'fallback=None\n'
                'if os.environ["FIXTURE_FALLBACK"]=="1":\n'
                ' env=dict(os.environ,CODEX_CLEF_ENABLED="0");env.pop("CODEX_CLEF_ROUTING_MODE",None)\n'
                ' fallback=([sys.executable,sys.argv[2],"task"],env)\n'
                'options={"fallback":fallback} if fallback is not None else {}\n'
                'raise SystemExit(launch_interactive(sys.executable,[sys.executable,sys.argv[2],"--no-daemon","task"],dict(os.environ),backoff=0,**options))\n'
            )
            env = dict(
                os.environ,
                FIXTURE_ROOT=str(root),
                FIXTURE_MODE=mode,
                FIXTURE_ERROR=error,
                CODEX_CLEF_ENABLED="0" if ordinary else "1",
                CODEX_CLEF_ROUTING_MODE="shadow",
                CODEX_HOME=str(root / "codex"),
                FIXTURE_FALLBACK=str(int(fallback)),
                FIXTURE_UNSAFE_DAEMON=str(int(unsafe_daemon)),
            )
            master, slave = pty.openpty()
            proc = subprocess.Popen(
                ([sys.executable, str(SOURCE / "launch.py"), sys.executable, str(SOURCE), str(fake), "--no-daemon", "task"]
                 if ordinary else [sys.executable, str(runner), str(SOURCE), str(fake)]),
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

    def test_ordinary_launcher_recovers_exact_bootstrap_failure(self):
        status, count, output, observed, _ = self.exercise("retry", ordinary=True)
        self.assertEqual((status, count), (0, 3))
        self.assertEqual(observed["args"], ["--no-daemon", "task"])
        self.assertEqual(observed["enabled"], "0")
        self.assertTrue(observed["stdin_tty"])
        self.assertTrue(observed["stdout_tty"])
        self.assertIn("KEY:hello", output)

    def test_ordinary_launcher_does_not_restart_other_errors_or_completed_sessions(self):
        for mode, error, sig, expected in (
            ("other", "Error: permission denied", None, 1),
            ("success", TIMEOUT, None, 0),
            ("interrupt", TIMEOUT, signal.SIGTERM, 143),
        ):
            with self.subTest(mode=mode):
                status, count, _, _, _ = self.exercise(mode, error, sig, ordinary=True)
                self.assertEqual((status, count), (expected, 1))

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

    def test_exact_timeout_uses_ordinary_path_once_without_assisted_environment(self):
        status, count, output, observed, _ = self.exercise("fallback", fallback=True)
        self.assertEqual((status, count), (0, 2))
        self.assertEqual(observed["args"], ["task"])
        self.assertEqual(observed["enabled"], "0")
        self.assertIsNone(observed["routing_mode"])
        self.assertTrue(observed["stdin_tty"])
        self.assertTrue(observed["stdout_tty"])
        self.assertIn("KEY:hello", output)
        self.assertIn("ordinary Codex", output)
        self.assertNotIn("retrying startup", output)

    def test_ordinary_path_failure_is_final(self):
        status, count, _, _, _ = self.exercise("exhaust", fallback=True)
        self.assertEqual((status, count), (1, 2))

    def test_unverified_daemon_keeps_assisted_retries(self):
        status, count, output, observed, _ = self.exercise(
            "fallback", fallback=True, unsafe_daemon=True
        )
        self.assertEqual((status, count), (1, 3))
        self.assertEqual(observed["args"], ["--no-daemon", "task"])
        self.assertEqual(observed["enabled"], "1")
        self.assertEqual(output.count("fallback skipped"), 1)
        self.assertNotIn("trying ordinary Codex", output)

    def test_other_errors_success_and_cancellation_do_not_use_ordinary_path(self):
        for mode, error, sig, expected in (
            ("other", "Error: permission denied", None, 1),
            ("success", TIMEOUT, None, 0),
            ("interrupt", TIMEOUT, signal.SIGTERM, 143),
        ):
            with self.subTest(mode=mode):
                status, count, output, observed, _ = self.exercise(mode, error, sig, True)
                self.assertEqual((status, count), (expected, 1))
                self.assertEqual(observed["enabled"], "1")
                self.assertNotIn("ordinary Codex", output)


class OrdinaryLaunchTests(unittest.TestCase):
    def test_terminfo_keeps_existing_profiles_custom_paths_and_default_search(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("ordinary_launch", SOURCE / "launch.py")
        launch = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(launch)
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            installed = home / ".nix-profile/share/terminfo"
            installed.mkdir(parents=True)
            absent = home / ".local/state/nix/profile/share/terminfo"
            custom = home / "custom missing terminfo"
            raw = os.pathsep.join([str(installed), str(absent), str(custom), ""])
            with patch.dict(os.environ, {"HOME": str(home), "TERMINFO_DIRS": raw}):
                launch.normalize_terminfo_search()
                self.assertEqual(os.environ["TERMINFO_DIRS"], os.pathsep.join([str(installed), str(custom), ""]))

    def test_only_local_interactive_terminal_sessions_are_supervised(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("ordinary_launch", SOURCE / "launch.py")
        launch = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(launch)
        sys.path.insert(0, str(SOURCE))
        from clef import startup
        for arguments, tty, assisted, supervised in (
            ([], True, False, True),
            (["--no-daemon", "resume"], True, False, True),
            (["--remote", "ws://example", "resume"], True, False, False),
            (["doctor", "--json"], True, False, False),
            (["exec", "task"], True, False, False),
            (["--help"], True, False, False),
            (["resume"], False, False, False),
            (["resume"], True, True, False),
        ):
            with self.subTest(arguments=arguments, tty=tty, assisted=assisted):
                with patch.object(sys, "argv", ["launch.py", "/native", str(SOURCE), *arguments]), \
                     patch.object(sys.stdin, "isatty", return_value=tty), \
                     patch.object(sys.stdout, "isatty", return_value=tty), \
                     patch.object(sys.stderr, "isatty", return_value=tty), \
                     patch.dict(os.environ, {"CODEX_CLEF_ENABLED": "1" if assisted else "0"}), \
                     patch.object(startup, "launch_interactive", return_value=17) as recover, \
                     patch.object(os, "execv") as execute:
                    result = launch.main()
                    if supervised:
                        self.assertEqual(result, 17)
                        recover.assert_called_once()
                        self.assertEqual(recover.call_args.args[:2], ("/native", ["/native", *arguments]))
                        execute.assert_not_called()
                    else:
                        execute.assert_called_once_with("/native", ["/native", *arguments])
                        recover.assert_not_called()


class StartupFailureTests(unittest.TestCase):
    def setUp(self):
        sys.path.insert(0, str(SOURCE))
        from clef import startup

        self.startup = startup
        self.spawn = subprocess.Popen
        self.children = []

    def test_daemon_metadata_access_failure_is_closed(self):
        with patch.object(self.startup.Path, "stat", side_effect=PermissionError):
            self.assertFalse(self.startup._ordinary_daemon_safe({"CODEX_CLEF_ENABLED":"0"}))

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
