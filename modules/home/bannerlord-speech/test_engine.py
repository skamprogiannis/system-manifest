"""Worker preparation discards audio and both English frontends share one model."""
import io
import json
import tempfile
import threading
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch

import engine


class WorkerPreparationTests(unittest.TestCase):
    def test_warmup_reports_device_without_starting_a_recorder(self):
        with tempfile.TemporaryDirectory() as folder:
            native = engine.NativeEngine(folder)
            worker = MagicMock()
            worker.poll.return_value = None
            worker.stdin = io.StringIO()
            worker.stdout = io.StringIO('{"ready": true, "device": "cuda", "device_fallback": null}\n')
            selector = MagicMock()
            selector.__enter__.return_value = selector
            selector.select.return_value = [True]
            with patch.object(engine.subprocess, 'Popen', return_value=worker) as popen, patch.object(engine.selectors, 'DefaultSelector', return_value=selector):
                native.warmup()
            self.assertEqual(worker.stdin.getvalue(), '{"operation": "prepare"}\n')
            self.assertEqual(popen.call_count, 1)
            self.assertEqual(popen.call_args.args[0][-3:], ['--device', native.requested_device, '--tts-worker'])
            self.assertIsNone(native.record_process)
            self.assertIsNone(native.record_dir)
            self.assertEqual(native.device, 'cuda')
            self.assertIsNone(native.device_fallback)

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

    def test_failed_worker_does_not_leave_a_stale_ready_device(self):
        with tempfile.TemporaryDirectory() as folder:
            native = engine.NativeEngine(folder, device='cuda')
            worker = MagicMock()
            worker.poll.return_value = None
            worker.stdin = io.StringIO()
            worker.stdout = io.StringIO('{"error":"RuntimeError","device":"cuda","device_fallback":null}\n')
            native.worker = worker
            native.device = 'cuda'
            selector = MagicMock()
            selector.__enter__.return_value = selector
            selector.select.return_value = [True]
            with patch.object(engine.selectors, 'DefaultSelector', return_value=selector):
                with self.assertRaises(RuntimeError):
                    native.synthesize('Welcome.', 'bm_george', 1.0)
            self.assertIsNone(native.worker)
            self.assertEqual(native.device, 'pending')
            self.assertIsNone(native.device_fallback)

    def test_bad_language_never_constructs_an_unrequested_pipeline(self):
        factory = MagicMock()
        with self.assertRaises(ValueError):
            engine.pipeline_for_voice('xx_unknown', {}, object(), factory)
        factory.assert_not_called()


class DevicePreparationTests(unittest.TestCase):
    def setUp(self):
        self.torch = MagicMock()
        self.torch.cuda.is_available.return_value = True
        self.models = []
        def model_factory():
            model = MagicMock()
            model.eval.return_value = model
            model.to.return_value = model
            self.models.append(model)
            return model
        self.model_factory = MagicMock(side_effect=model_factory)
        self.rendered = []
        self.factories = []
        def pipeline_factory(**kwargs):
            self.factories.append(kwargs)
            def render(text, voice, speed):
                self.rendered.append((kwargs['device'], kwargs['lang_code'], text, voice, speed))
                result = MagicMock()
                result.audio.numpy.return_value = [0.0]
                yield result
            return render
        self.pipeline_factory = pipeline_factory

    def prepare(self, device):
        return engine.prepare_speech(self.torch, self.model_factory, self.pipeline_factory, device, Path('/fixture/voices'))

    def test_auto_selects_cuda_and_warms_both_frontends_before_returning(self):
        model, pipelines, device, fallback = self.prepare('auto')
        self.assertEqual((device, fallback), ('cuda', None))
        self.assertIs(model, self.models[0])
        self.assertEqual(set(pipelines), {'a', 'b'})
        self.assertTrue(all(item['model'] is model for item in self.factories))
        self.assertEqual({item[:2] for item in self.rendered}, {('cuda', 'a'), ('cuda', 'b')})
        self.assertTrue(all(item[3].endswith('.pt') and item[4] == 1.0 for item in self.rendered))
        self.models[0].to.assert_called_once_with('cuda')

    def test_cpu_selection_does_not_probe_or_initialize_cuda(self):
        model, pipelines, device, fallback = self.prepare('cpu')
        self.assertEqual((device, fallback), ('cpu', None))
        self.torch.cuda.is_available.assert_not_called()
        self.torch.cuda.empty_cache.assert_not_called()
        self.models[0].to.assert_called_once_with('cpu')
        self.assertEqual({item[:2] for item in self.rendered}, {('cpu', 'a'), ('cpu', 'b')})

    def test_unavailable_cuda_falls_back_to_cpu_with_bounded_category(self):
        self.torch.cuda.is_available.return_value = False
        for requested in ('auto', 'cuda'):
            with self.subTest(requested=requested):
                model, pipelines, device, fallback = self.prepare(requested)
                self.assertEqual((device, fallback), ('cpu', 'cuda_unavailable'))
                model.to.assert_called_once_with('cpu')

    def test_cuda_model_initialization_failure_rebuilds_and_warms_cpu_model(self):
        original = self.model_factory.side_effect
        def factory():
            model = original()
            if len(self.models) == 1:
                model.to.side_effect = RuntimeError('private device detail')
            return model
        self.model_factory.side_effect = factory
        model, pipelines, device, fallback = self.prepare('cuda')
        self.assertEqual((device, fallback), ('cpu', 'cuda_initialization_failed'))
        self.assertIs(model, self.models[1])
        self.assertTrue(all(item['model'] is model for item in self.factories))
        self.torch.cuda.empty_cache.assert_called_once()

    def test_cuda_warm_inference_failure_discards_cuda_frontends_then_warms_cpu(self):
        original = self.pipeline_factory
        def factory(**kwargs):
            if kwargs['device'] == 'cuda':
                def fail(*args, **options):
                    raise RuntimeError('CUDA kernel launch failed')
                return fail
            return original(**kwargs)
        self.pipeline_factory = factory
        model, pipelines, device, fallback = self.prepare('auto')
        self.assertEqual((device, fallback), ('cpu', 'cuda_initialization_failed'))
        self.assertIs(model, self.models[1])
        self.assertEqual({item[:2] for item in self.rendered}, {('cpu', 'a'), ('cpu', 'b')})
        self.torch.cuda.empty_cache.assert_called_once()

    def test_cpu_failure_propagates_and_invalid_device_does_not_load_model(self):
        self.model_factory.side_effect = RuntimeError('Missing pinned model')
        with self.assertRaises(RuntimeError):
            self.prepare('cpu')
        self.model_factory.reset_mock()
        with self.assertRaises(ValueError):
            self.prepare('unexpected')
        self.model_factory.assert_not_called()


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
