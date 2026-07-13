import os
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

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

    @patch.dict(os.environ, {"OPENAI_API_KEY": "test-key"})
    def test_openai_realtime_uses_supported_voice_reasoning_and_transcription(
        self,
    ) -> None:
        session = agent.build_session(
            runtime={
                "architecture": "realtime",
                "provider": "openai",
                "model": "gpt-realtime-2.1",
                "voice": "marin",
                "language": "tr",
            }
        )

        options = session.llm._opts

        self.assertEqual(options.model, "gpt-realtime-2.1")
        self.assertEqual(options.voice, "marin")
        self.assertEqual(options.reasoning.effort, "low")
        self.assertEqual(options.input_audio_transcription.model, "gpt-realtime-whisper")
        self.assertEqual(options.input_audio_transcription.language, "tr")
        self.assertEqual(options.turn_detection.type, "semantic_vad")
        self.assertEqual(options.turn_detection.eagerness, "medium")

    def test_openai_realtime_requires_an_api_key(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "OPENAI_API_KEY"):
                agent.build_session(
                    runtime={
                        "architecture": "realtime",
                        "provider": "openai",
                        "model": "gpt-realtime-2.1",
                        "voice": "marin",
                        "language": "tr",
                    }
                )

    def test_realtime_rejects_unknown_providers(self) -> None:
        with self.assertRaisesRegex(ValueError, "Unsupported realtime provider: unknown"):
            agent.build_session(runtime={"architecture": "realtime", "provider": "unknown"})


class WorkerOptionsTest(unittest.TestCase):
    @patch.dict(os.environ, {"VOICE_AGENT_MAX_CONCURRENT_JOBS": "10"})
    def test_worker_load_uses_active_job_cap(self) -> None:
        server = SimpleNamespace(active_jobs=[object()] * 5)

        self.assertEqual(agent.worker_load(server), 0.5)

    @patch.dict(
        os.environ,
        {
            "VOICE_AGENT_HEALTH_PORT": "9190",
            "VOICE_AGENT_PROMETHEUS_PORT": "9191",
            "VOICE_AGENT_MAX_CONCURRENT_JOBS": "10",
        },
    )
    def test_worker_options_expose_health_metrics_and_load_shedding(self) -> None:
        options = agent.build_worker_options()

        self.assertEqual(options.port, 9190)
        self.assertEqual(options.prometheus_port, 9191)
        self.assertEqual(options.load_threshold, 0.95)


class VoiceAssistantTest(unittest.TestCase):
    def test_default_greeting_matches_language(self) -> None:
        turkish = agent.VoiceAssistant("call-tr", "instructions", language="tr")
        english = agent.VoiceAssistant("call-en", "instructions", language="en")

        self.assertTrue(turkish._default_greeting().startswith("Merhaba"))
        self.assertTrue(english._default_greeting().startswith("Hello"))

    def test_pipeline_agent_does_not_require_a_realtime_metrics_session(self) -> None:
        assistant = agent.VoiceAssistant("call-pipeline", "instructions")

        assistant._bind_realtime_metrics()


class ImprovementBudgetTest(unittest.IsolatedAsyncioTestCase):
    def test_duration_uses_the_reserved_test_allowance(self) -> None:
        context = {"call": {"test_duration_limit_seconds": 20}}

        self.assertEqual(agent.improvement_budget_duration_seconds(context), 20.0)

    def test_duration_is_disabled_without_a_positive_allowance(self) -> None:
        self.assertIsNone(agent.improvement_budget_duration_seconds({"call": {}}))
        self.assertIsNone(
            agent.improvement_budget_duration_seconds(
                {"call": {"test_duration_limit_seconds": "invalid"}}
            )
        )
        self.assertIsNone(
            agent.improvement_budget_duration_seconds(
                {"call": {"test_duration_limit_seconds": 0}}
            )
        )

    async def test_enforcement_ends_the_call_after_the_remaining_delay(self) -> None:
        end_call = AsyncMock()
        sleep = AsyncMock()
        with patch.object(agent, "improvement_budget_duration_seconds", return_value=2.5):
            with patch.object(agent.asyncio, "sleep", sleep):
                await agent.enforce_improvement_budget({"call": {}}, end_call)

        sleep.assert_awaited_once_with(2.5)
        end_call.assert_awaited_once_with("ai_improvement_credit_limit")

    async def test_budget_starts_only_after_the_customer_join_is_recorded(self) -> None:
        context = {"call": {"test_duration_limit_seconds": 20}}
        chatwoot = SimpleNamespace(record_event=AsyncMock())
        end_call = AsyncMock()
        background_task = Mock()
        with patch.object(agent, "enforce_improvement_budget", new=Mock(return_value="budget-coro")) as enforce_budget:
            with patch.object(agent, "_fire_and_forget", return_value=background_task) as fire_and_forget:
                result = await agent.start_improvement_budget(
                    context,
                    chatwoot,
                    "call-1",
                    "customer-1",
                    end_call,
                )

        chatwoot.record_event.assert_awaited_once_with(
            "call-1",
            "test_call_customer_joined",
            {"participant_identity": "customer-1"},
        )
        enforce_budget.assert_called_once_with(context, end_call)
        fire_and_forget.assert_called_once_with("improvement_budget", "budget-coro")
        self.assertIs(result, background_task)


class VoiceToolTest(unittest.IsolatedAsyncioTestCase):
    async def test_terminal_tool_result_stops_agent_input(self) -> None:
        chatwoot = SimpleNamespace(execute_tool=AsyncMock(return_value={"result": {"terminal_action": "handoff", "handoff_status": "requested"}}))
        session_input = Mock()
        context = SimpleNamespace(session=SimpleNamespace(input=session_input))
        tool = agent.build_chatwoot_tool(
            {
                "key": "human_handoff",
                "name": "human_handoff",
                "description": "Transfer the caller",
                "input_schema": {"type": "object", "properties": {}},
            },
            chatwoot,
            "call-1",
        )

        await tool._func({}, context)

        session_input.set_audio_enabled.assert_called_once_with(False)


if __name__ == "__main__":
    unittest.main()
