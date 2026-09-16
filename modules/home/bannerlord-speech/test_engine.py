"""English voice frontends share one CPU model."""
import unittest
from unittest.mock import MagicMock

import engine


class VoicePipelineTests(unittest.TestCase):
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


if __name__ == '__main__':
    unittest.main()
