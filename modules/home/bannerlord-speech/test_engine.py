"""Worker preparation is silent and both English frontends share one model."""
import io
import json
import tempfile
import threading
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch

import engine


class WorkerPreparationTests(unittest.TestCase):
    def test_warmup_initializes_worker_without_an_utterance_or_recorder(self):
        with tempfile.TemporaryDirectory() as folder:
            native = engine.NativeEngine(folder)
            worker = MagicMock()
            worker.poll.return_value = None
            worker.stdin = io.StringIO()
            worker.stdout = io.StringIO('{"ready": true}\n')
            selector = MagicMock()
            selector.__enter__.return_value = selector
            selector.select.return_value = [True]
            with patch.object(engine.subprocess, 'Popen', return_value=worker) as popen, patch.object(engine.selectors, 'DefaultSelector', return_value=selector):
                native.warmup()
            self.assertEqual(worker.stdin.getvalue(), '{"operation": "prepare"}\n')
            self.assertEqual(popen.call_count, 1)
            self.assertEqual(popen.call_args.args[0][-1], '--tts-worker')
            self.assertIsNone(native.record_process)
            self.assertIsNone(native.record_dir)

    def test_preparation_and_synthesis_share_the_same_total_deadline(self):
        with tempfile.TemporaryDirectory() as folder:
            native = engine.NativeEngine(folder)
            native.worker_lock = MagicMock()
            native.worker_lock.acquire.return_value = True
            worker = MagicMock()
            worker.poll.return_value = None
            worker.stdin = io.StringIO()
            worker.stdout = io.StringIO()
            native.worker = worker
            selector = MagicMock()
            selector.__enter__.return_value = selector
            selector.select.return_value = []
            with patch.object(engine.time, 'monotonic', side_effect=[100, 140]), patch.object(engine.selectors, 'DefaultSelector', return_value=selector):
                with self.assertRaises(TimeoutError):
                    native.synthesize('A short reply.', 'bm_lewis', 1.0)
            native.worker_lock.acquire.assert_called_once_with(timeout=45)
            selector.select.assert_called_once_with(5)
            worker.kill.assert_called_once()
            native.worker_lock.release.assert_called_once()
            self.assertIsNone(native.worker)

    def test_american_and_british_voices_use_matching_cached_frontends_and_shared_weights(self):
        model = object()
        pipelines = {}
        factory = MagicMock(side_effect=lambda **kwargs: object())
        british = engine.pipeline_for_voice('bm_lewis', pipelines, model, factory)
        american = engine.pipeline_for_voice('am_fenrir', pipelines, model, factory)
        self.assertIs(engine.pipeline_for_voice('bf_alice', pipelines, model, factory), british)
        self.assertIs(engine.pipeline_for_voice('af_heart', pipelines, model, factory), american)
        self.assertEqual(factory.call_count, 2)
        self.assertEqual([call.kwargs['lang_code'] for call in factory.call_args_list], ['b', 'a'])
        self.assertTrue(all(call.kwargs['model'] is model for call in factory.call_args_list))
        self.assertTrue(all(call.kwargs['device'] == 'cpu' for call in factory.call_args_list))

    def test_bad_language_never_constructs_an_unrequested_pipeline(self):
        factory = MagicMock()
        with self.assertRaises(ValueError):
            engine.pipeline_for_voice('xx_unknown', {}, object(), factory)
        factory.assert_not_called()


class ShortSpeechTests(unittest.TestCase):
    def test_short_phrases_preserve_words_and_bound_synthesis_units(self):
        text = 'My household requires loyal service. ' + 'Honour must be earned by deeds, not promises. ' * 8
        parts = engine.split_speech_text(text)
        self.assertTrue(all(0 < len(part) <= 120 for part in parts))
        self.assertEqual(' '.join(parts).split(), text.split())

    def test_cancel_between_chunks_does_not_generate_the_remaining_text(self):
        calls = []
        cancelled = False
        def pipeline(text, **kwargs):
            nonlocal cancelled
            calls.append(text)
            result = MagicMock(); result.audio.numpy.return_value = [0]
            yield result
            cancelled = True
        with self.assertRaises(engine.SpeechCancelled):
            engine.render_speech_parts(pipeline, 'A loyal household needs brave service. ' * 9, 'fixture', 1, lambda: cancelled)
        self.assertEqual(len(calls), 1)

    def test_pre_cancelled_request_does_not_start_a_worker(self):
        with tempfile.TemporaryDirectory() as directory:
            native = engine.NativeEngine(directory)
            cancelled = threading.Event(); cancelled.set()
            with patch.object(engine.subprocess, 'Popen') as popen:
                with self.assertRaises(engine.SpeechCancelled):
                    native.synthesize('Obsolete.', 'bm_lewis', 1, cancel_event=cancelled)
                popen.assert_not_called()
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_worker_cancel_response_preserves_loaded_worker_and_removes_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            native = engine.NativeEngine(directory)
            worker = MagicMock(); worker.poll.return_value = None
            worker.stdin = io.StringIO(); worker.stdout = io.StringIO('{"cancelled":true}\n')
            native.worker = worker
            cancelled = threading.Event()
            selector = MagicMock(); selector.__enter__.return_value = selector
            def ready(timeout):
                if not cancelled.is_set():
                    cancelled.set()
                    return []
                request = json.loads(worker.stdin.getvalue())
                self.assertTrue(Path(request['cancel_path']).exists())
                return [True]
            selector.select.side_effect = ready
            with patch.object(engine.selectors, 'DefaultSelector', return_value=selector):
                with self.assertRaises(engine.SpeechCancelled):
                    native.synthesize('Obsolete.', 'bm_lewis', 1, cancel_event=cancelled)
            worker.kill.assert_not_called()
            self.assertIs(native.worker, worker)
            self.assertEqual(list(Path(directory).iterdir()), [])


if __name__ == '__main__':
    unittest.main()
