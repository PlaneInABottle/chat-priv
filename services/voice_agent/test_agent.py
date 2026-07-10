import os
import unittest
from unittest.mock import patch

import agent


class BuildSessionTest(unittest.TestCase):
    @patch.dict(os.environ, {"GOOGLE_API_KEY": "test-key"})
    def test_gemini_realtime_uses_provider_managed_context_compression(self) -> None:
        session = agent.build_session(
            runtime={
                "architecture": "realtime",
                "provider": "gemini",
                "model": "gemini-3.1-flash-live-preview",
                "voice": "Charon",
            }
        )

        compression = session.llm._opts.context_window_compression

        self.assertIsNotNone(compression.sliding_window)
        self.assertIsNone(compression.trigger_tokens)
        self.assertIsNone(compression.sliding_window.target_tokens)


if __name__ == "__main__":
    unittest.main()
