from __future__ import annotations

import tempfile
import unittest
import wave
from pathlib import Path

from run_scenario import (
    Assertions,
    HarnessError,
    assertion_failures,
    load_wav_fixture,
)


class LoadWavFixtureTest(unittest.TestCase):
    def test_chunks_pcm_once_without_padding_the_final_frame(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.wav"
            sample_rate = 16_000
            sample_count = 650
            with wave.open(str(path), "wb") as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(sample_rate)
                output.writeframes(bytes(sample_count * 2))

            fixture = load_wav_fixture(path)

        self.assertEqual(fixture.sample_rate, sample_rate)
        self.assertEqual([len(frame) for frame in fixture.frames], [640, 640, 20])
        self.assertAlmostEqual(fixture.duration_seconds, sample_count / sample_rate)

    def test_rejects_non_mono_audio(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "stereo.wav"
            with wave.open(str(path), "wb") as output:
                output.setnchannels(2)
                output.setsampwidth(2)
                output.setframerate(16_000)
                output.writeframes(bytes(1_280))

            with self.assertRaisesRegex(HarnessError, "mono, 16-bit PCM"):
                load_wav_fixture(path)


class AssertionFailuresTest(unittest.TestCase):
    def setUp(self) -> None:
        self.expected = Assertions(
            caller_text=None,
            ai_text=None,
            tools=(),
            require_caller_transcript=True,
            require_ai_transcript=True,
            require_agent_audio=True,
        )

    def test_does_not_treat_greeting_as_reply_to_caller(self) -> None:
        call = {
            "transcript_segments": [
                {"role": "ai", "text": "Merhaba"},
                {"role": "caller", "text": "Siparisimi soracaktim"},
            ],
            "tool_events": [],
        }

        self.assertEqual(
            assertion_failures(call, self.expected),
            ["AI transcript after the caller turn is missing"],
        )

    def test_ai_text_expectation_does_not_match_the_greeting(self) -> None:
        expected = Assertions(
            caller_text=None,
            ai_text="merhaba",
            tools=(),
            require_caller_transcript=True,
            require_ai_transcript=False,
            require_agent_audio=False,
        )
        call = {
            "transcript_segments": [
                {"role": "ai", "text": "Merhaba"},
                {"role": "caller", "text": "Bir sorum var"},
            ],
            "tool_events": [],
        }

        self.assertEqual(
            assertion_failures(call, expected),
            ["AI transcript does not contain 'merhaba'"],
        )

    def test_accepts_reply_and_executed_tool(self) -> None:
        expected = Assertions(
            caller_text="siparis",
            ai_text="yardimci",
            tools=("ikas_lookup_order",),
            require_caller_transcript=True,
            require_ai_transcript=True,
            require_agent_audio=True,
        )
        call = {
            "transcript_segments": [
                {"role": "caller", "text": "Siparis durumunu ogrenebilir miyim?"},
                {"role": "ai", "text": "Tabii, yardimci olayim."},
            ],
            "tool_events": [{"tool": "ikas_lookup_order", "status": "executed"}],
        }

        self.assertEqual(assertion_failures(call, expected), [])

    def test_rejects_failed_tool_event(self) -> None:
        expected = Assertions(
            caller_text=None,
            ai_text=None,
            tools=("human_handoff",),
            require_caller_transcript=False,
            require_ai_transcript=False,
            require_agent_audio=False,
        )
        call = {
            "transcript_segments": [],
            "tool_events": [{"tool": "human_handoff", "status": "failed"}],
        }

        self.assertEqual(
            assertion_failures(call, expected),
            [
                "executed tool 'human_handoff' expected 1 time(s), got 0",
                "tool 'human_handoff' has 1 non-executed event(s)",
            ],
        )

    def test_rejects_duplicate_tool_execution(self) -> None:
        expected = Assertions(
            caller_text=None,
            ai_text=None,
            tools=("human_handoff",),
            require_caller_transcript=False,
            require_ai_transcript=False,
            require_agent_audio=False,
        )
        call = {
            "transcript_segments": [],
            "tool_events": [
                {"tool": "human_handoff", "status": "executed"},
                {"tool": "human_handoff", "status": "executed"},
            ],
        }

        self.assertEqual(
            assertion_failures(call, expected),
            ["executed tool 'human_handoff' expected 1 time(s), got 2"],
        )


if __name__ == "__main__":
    unittest.main()
