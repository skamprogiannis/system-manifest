"""Focused tests for the desktop dictation command wrapper."""
import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest

SOURCE = Path(__file__).with_name('client.py')
SPEC = importlib.util.spec_from_file_location('desktop_dictation_client', SOURCE)
client = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(client)


class ClientTests(unittest.TestCase):
    def test_detects_bannerlord_using_the_full_command_line(self):
        calls = []
        original = client.subprocess.run
        try:
            def run(args, **kwargs):
                calls.append((args, kwargs))
                return SimpleNamespace(returncode=0)
            client.subprocess.run = run
            self.assertTrue(client.game_is_open())
        finally:
            client.subprocess.run = original
        self.assertEqual(calls[0][0][:2], ['pgrep', '-f'])
        self.assertIn('Bannerlord', calls[0][0][2])

    def test_stop_copies_text_without_conflicting_stdin(self):
        with TemporaryDirectory() as directory:
            runtime = Path(directory)
            calls = []
            original_runtime, original_request = client.runtime_dir, client.request
            original_run, original_notify, original_stop = client.subprocess.run, client.notify, client.stop_service
            try:
                client.runtime_dir = lambda: runtime
                client.state_path().write_text('recording\n')
                client.request = lambda *_args, **_kwargs: {'text': 'private local text'}
                client.subprocess.run = lambda args, **kwargs: calls.append((args, kwargs)) or SimpleNamespace(returncode=0)
                client.notify = lambda *_args, **_kwargs: None
                client.stop_service = lambda: None
                self.assertEqual(client.stop(), 0)
            finally:
                client.runtime_dir, client.request = original_runtime, original_request
                client.subprocess.run, client.notify, client.stop_service = original_run, original_notify, original_stop
        self.assertFalse((runtime / 'recording').exists())
        self.assertEqual(calls[0][0], ['wl-copy'])
        self.assertEqual(calls[0][1]['input'], b'private local text')
        self.assertNotIn('stdin', calls[0][1])


if __name__ == '__main__':
    unittest.main()
