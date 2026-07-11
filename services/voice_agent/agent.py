import asyncio
import hashlib
import json
import logging
import os
import uuid
from typing import Any

import aiohttp
from dotenv import load_dotenv
from google.genai import types as google_types
from livekit import agents, rtc
from livekit.agents import (
    Agent,
    AgentSession,
    AutoSubscribe,
    RoomInputOptions,
    RunContext,
    function_tool,
    inference,
)
from livekit.agents.llm import ChatMessage
from livekit.agents.llm import ToolError
from livekit.plugins import google, openai
from openai.types.realtime import AudioTranscription, RealtimeReasoning
from openai.types.realtime.realtime_audio_input_turn_detection import SemanticVad

load_dotenv()

logger = logging.getLogger("voice_agent")

DEFAULT_BASE_INSTRUCTIONS = (
    "You are Kozmopath's Turkish customer support voice assistant. "
    "Speak only in natural Istanbul Turkish unless the caller explicitly asks for another language. "
    "Use clear Turkish pronunciation, short sentences, and a calm professional support tone. "
    "Do not mix English into Turkish answers unless a product name, brand, or technical term requires it. "
    "Treat unclear multilingual-looking speech as possible speech-to-text noise; prefer a plausible Turkish interpretation "
    "and ask a short Turkish clarification when unsure. "
    "Avoid long lists on voice calls; ask one short clarification question when needed. "
    "If the caller asks for a human, call request_human_handoff."
)
DEFAULT_REALTIME_MODEL = "gemini-3.1-flash-live-preview"
DEFAULT_OPENAI_REALTIME_MODEL = "gpt-realtime-2.1"
DEFAULT_OPENAI_REALTIME_VOICE = "marin"


_REQUIRED_ENV_VARS = ["CHATWOOT_INTERNAL_API_URL", "VOICE_AGENT_INTERNAL_TOKEN"]


def _validate_env() -> None:
    missing = [name for name in _REQUIRED_ENV_VARS if not os.environ.get(name)]
    if missing:
        raise RuntimeError(f"Missing required environment variables: {', '.join(missing)}")


class ChatwootClient:
    def __init__(self) -> None:
        _validate_env()
        self.base_url = os.environ["CHATWOOT_INTERNAL_API_URL"].rstrip("/")
        self.token = os.environ["VOICE_AGENT_INTERNAL_TOKEN"]
        self._session: aiohttp.ClientSession | None = None

    @property
    def session(self) -> aiohttp.ClientSession:
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                headers={"X-Voice-Agent-Token": self.token},
                raise_for_status=True,
            )
        return self._session

    async def close(self) -> None:
        if self._session and not self._session.closed:
            await self._session.close()
            self._session = None

    async def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        async with self.session.post(f"{self.base_url}{path}", json=payload) as response:
            return await response.json()

    async def get(self, path: str) -> dict[str, Any]:
        async with self.session.get(f"{self.base_url}{path}") as response:
            return await response.json()

    async def agent_context(self, provider_call_id: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        async with self.session.post(
            f"{self.base_url}/internal/voice/calls/{provider_call_id}/agent_context",
            json={"metadata": metadata or {}},
            raise_for_status=False,
        ) as response:
            payload = await response.json()
            if response.status >= 400:
                raise AgentContextRejected(response.status, str(payload.get("error") or response.reason))

            return payload

    async def execute_tool(
        self,
        provider_call_id: str,
        tool_key: str,
        arguments: dict[str, Any],
        external_id: str,
    ) -> dict[str, Any]:
        return await self.post(
            f"/internal/voice/calls/{provider_call_id}/tools/{tool_key}/execute",
            {"arguments": arguments, "external_id": external_id},
        )

    async def request_handoff(self, provider_call_id: str, reason: str) -> dict[str, Any]:
        return await self.post(f"/internal/voice/calls/{provider_call_id}/handoff", {"reason": reason})

    async def end_call(self, provider_call_id: str, end_reason: str) -> dict[str, Any]:
        return await self.post(f"/internal/voice/calls/{provider_call_id}/end", {"end_reason": end_reason})

    async def record_event(self, provider_call_id: str, event: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        return await self.post(
            f"/internal/voice/calls/{provider_call_id}/event",
            {"event": event, "payload": payload or {}},
        )

    async def record_tool_call(
        self,
        provider_call_id: str,
        tool: str,
        status: str,
        arguments: dict[str, Any],
        result: dict[str, Any],
        error_message: str | None,
        duration_ms: int,
        external_id: str | None = None,
    ) -> dict[str, Any]:
        payload = {
            "tool": tool,
            "status": status,
            "arguments": arguments,
            "result": result,
            "error_message": error_message,
            "duration_ms": duration_ms,
        }
        if external_id:
            payload["external_id"] = external_id
        return await self.post(
            f"/internal/voice/calls/{provider_call_id}/tool_call",
            payload,
        )

    async def append_transcript(
        self,
        provider_call_id: str,
        role: str,
        text: str,
        source: str,
        metadata: dict[str, Any],
    ) -> dict[str, Any]:
        payload = {"role": role, "text": text, "source": source, "metadata": metadata}
        external_id = metadata.get("external_segment_id")
        if external_id:
            payload["external_segment_id"] = external_id
        return await self.post(
            f"/internal/voice/calls/{provider_call_id}/transcript",
            payload,
        )


class AgentContextRejected(RuntimeError):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


class VoiceAssistant(Agent):
    def __init__(
        self,
        provider_call_id: str,
        instructions: str,
        greeting: str | None = None,
        tools: list[Any] | None = None,
        language: str = "tr",
        realtime_provider: str | None = None,
        realtime_model_name: str | None = None,
    ) -> None:
        self.provider_call_id = provider_call_id
        self.greeting = greeting
        self.language = language
        self.realtime_provider = realtime_provider
        self.realtime_model_name = realtime_model_name
        super().__init__(instructions=instructions, tools=tools or [])

    async def on_enter(self) -> None:
        self._bind_realtime_metrics()
        if self.realtime_model_name and "gemini-3.1" in self.realtime_model_name:
            logger.info(
                "skipping proactive greeting for room=%s model=%s reason=gemini_31_generate_reply_unsupported",
                self.provider_call_id,
                self.realtime_model_name,
            )
            return

        greeting = self.greeting or self._default_greeting()
        logger.info(
            "requesting proactive greeting for room=%s greeting_chars=%s",
            self.provider_call_id,
            len(greeting),
        )
        await self.session.generate_reply(instructions=f"Greet the caller naturally in {self.language} using this greeting: {greeting}")
        logger.info("proactive greeting requested for room=%s", self.provider_call_id)

    def _default_greeting(self) -> str:
        if self.language.lower().startswith("tr"):
            return "Merhaba, size nasil yardimci olabilirim?"

        return "Hello, how can I help you?"

    def _bind_realtime_metrics(self) -> None:
        if self.realtime_provider is None:
            return

        realtime_session = self.realtime_llm_session

        @realtime_session.on("metrics_collected")
        def on_metrics_collected(metrics: Any) -> None:
            logger.info(
                "realtime metrics room=%s provider=%s model=%s request_id=%s ttfa_seconds=%s duration_seconds=%s "
                "input_tokens=%s output_tokens=%s audio_input_tokens=%s audio_output_tokens=%s",
                self.provider_call_id,
                self.realtime_provider,
                self.realtime_model_name,
                getattr(metrics, "request_id", None),
                getattr(metrics, "ttft", None),
                getattr(metrics, "duration", None),
                getattr(metrics, "input_tokens", None),
                getattr(metrics, "output_tokens", None),
                getattr(getattr(metrics, "input_token_details", None), "audio_tokens", None),
                getattr(getattr(metrics, "output_token_details", None), "audio_tokens", None),
            )


def base_instructions() -> str:
    return os.getenv("VOICE_AGENT_INSTRUCTIONS", DEFAULT_BASE_INSTRUCTIONS)


def realtime_model() -> str:
    return os.getenv("VOICE_AGENT_REALTIME_MODEL", DEFAULT_REALTIME_MODEL)


def realtime_voice() -> str:
    return os.getenv("VOICE_AGENT_GEMINI_VOICE", "Charon")


def openai_realtime_model() -> str:
    return os.getenv("VOICE_AGENT_OPENAI_REALTIME_MODEL", DEFAULT_OPENAI_REALTIME_MODEL)


def openai_realtime_voice() -> str:
    return os.getenv("VOICE_AGENT_OPENAI_VOICE", DEFAULT_OPENAI_REALTIME_VOICE)


def resolve_realtime_runtime(runtime: dict[str, Any]) -> dict[str, str]:
    provider = str(runtime.get("provider") or os.getenv("VOICE_AGENT_REALTIME_PROVIDER", "gemini")).lower()
    if provider == "openai":
        default_model = openai_realtime_model()
        default_voice = openai_realtime_voice()
    else:
        default_model = realtime_model()
        default_voice = realtime_voice()

    return {
        "provider": provider,
        "model": str(runtime.get("model") or default_model),
        "voice": str(runtime.get("voice") or default_voice),
        "language": str(runtime.get("language") or os.getenv("VOICE_AGENT_LANGUAGE", "tr")),
    }


def instruction_fingerprint(instructions: str) -> str:
    return hashlib.sha256(instructions.encode("utf-8")).hexdigest()[:12]


def job_metadata(ctx: agents.JobContext) -> dict[str, Any]:
    raw_metadata = getattr(getattr(ctx, "job", None), "metadata", None)
    if not raw_metadata:
        return {}

    try:
        parsed = json.loads(raw_metadata)
    except json.JSONDecodeError:
        return {}

    return parsed if isinstance(parsed, dict) else {}


def session_instructions(metadata: dict[str, Any]) -> str:
    instructions = [base_instructions()]
    voice_instructions = str(metadata.get("voice_instructions") or "").strip()
    if voice_instructions:
        instructions.append(f"Store-specific voice instructions: {voice_instructions}")

    greeting = str(metadata.get("voice_greeting") or "").strip()
    if greeting:
        instructions.append(f"Preferred greeting: {greeting}")

    return "\n\n".join(instructions)


def raw_tool_schema(tool: dict[str, Any]) -> dict[str, Any]:
    return {
        "type": "function",
        "name": tool["name"],
        "description": tool.get("description") or tool["name"],
        "parameters": tool.get("input_schema") or {"type": "object", "properties": {}},
    }


def build_chatwoot_tool(tool: dict[str, Any], chatwoot: ChatwootClient, provider_call_id: str) -> Any:
    tool_key = str(tool["key"])

    async def handler(raw_arguments: dict[str, object], context: RunContext) -> str:
        external_id = f"{tool_key}-{uuid.uuid4().hex}"
        result = await chatwoot.execute_tool(
            provider_call_id,
            tool_key,
            dict(raw_arguments or {}),
            external_id,
        )
        payload = result.get("result", result)
        if result.get("status") in {"error", "rejected"} or payload.get("status") == "error":
            raise ToolError(payload.get("error_message") or "Tool execution failed.")

        if payload.get("terminal_action"):
            context.session.input.set_audio_enabled(False)

        return json.dumps(compact_tool_result(tool_key, payload), ensure_ascii=False)

    return function_tool(handler, raw_schema=raw_tool_schema(tool))


def build_chatwoot_tools(context: dict[str, Any], chatwoot: ChatwootClient, provider_call_id: str) -> list[Any]:
    return [build_chatwoot_tool(tool, chatwoot, provider_call_id) for tool in context.get("tools", [])]


def gemini_31_realtime_enabled() -> bool:
    return (
        voice_agent_architecture() == "realtime"
        and os.getenv("VOICE_AGENT_REALTIME_PROVIDER", "gemini") == "gemini"
        and "gemini-3.1" in realtime_model()
    )


def voice_agent_architecture() -> str:
    return os.getenv("VOICE_AGENT_ARCHITECTURE") or os.getenv("VOICE_AGENT_MODE", "pipeline")


def compact_tool_result(tool: str, result: dict[str, Any]) -> dict[str, Any]:
    if tool == "request_human_handoff":
        return compact_hash(
            result,
            [
                "tool_status",
                "terminal_action",
                "test_mode",
                "handoff_status",
                "ai_status",
                "reason",
                "customer_message",
            ],
        )
    if tool == "end_customer_call":
        return compact_hash(result, ["status", "end_reason", "duration_seconds"])

    return result


def compact_hash(payload: dict[str, Any], keys: list[str]) -> dict[str, Any]:
    return {key: payload[key] for key in keys if key in payload and payload[key] is not None}


def participant_wait_timeout() -> float:
    return float(os.getenv("VOICE_AGENT_WAIT_FOR_PARTICIPANT_TIMEOUT_SECONDS", "120"))


def is_customer_participant(participant: rtc.RemoteParticipant) -> bool:
    identity = participant.identity or ""
    if identity.startswith("agent-"):
        return False
    if participant.kind == rtc.ParticipantKind.PARTICIPANT_KIND_AGENT:
        return False
    return True


async def wait_for_customer_participant(
    ctx: agents.JobContext,
) -> rtc.RemoteParticipant:
    for participant in ctx.room.remote_participants.values():
        if is_customer_participant(participant):
            return participant

    loop = asyncio.get_running_loop()
    future: asyncio.Future[rtc.RemoteParticipant] = loop.create_future()

    def on_participant_connected(participant: rtc.RemoteParticipant) -> None:
        if not future.done() and is_customer_participant(participant):
            future.set_result(participant)

    ctx.room.on("participant_connected", on_participant_connected)
    try:
        return await asyncio.wait_for(future, timeout=participant_wait_timeout())
    finally:
        ctx.room.off("participant_connected", on_participant_connected)


def build_session(instructions: str | None = None, runtime: dict[str, Any] | None = None) -> AgentSession:
    resolved_instructions = instructions or base_instructions()
    runtime = runtime or {}
    architecture = runtime.get("architecture") or voice_agent_architecture()
    if architecture == "realtime":
        resolved_runtime = resolve_realtime_runtime(runtime)
        provider = resolved_runtime["provider"]
        if provider == "gemini":
            model = resolved_runtime["model"]
            voice = resolved_runtime["voice"]
            logger.info(
                "building Gemini realtime session model=%s voice=%s instructions_chars=%s instructions_sha256=%s",
                model,
                voice,
                len(resolved_instructions),
                instruction_fingerprint(resolved_instructions),
            )
            return AgentSession(
                llm=google.realtime.RealtimeModel(
                    model=model,
                    voice=voice,
                    temperature=float(os.getenv("VOICE_AGENT_TEMPERATURE", "0.8")),
                    instructions=resolved_instructions,
                    context_window_compression=google_types.ContextWindowCompressionConfig(
                        sliding_window=google_types.SlidingWindow(),
                    ),
                )
            )
        if provider == "openai":
            model = resolved_runtime["model"]
            voice = resolved_runtime["voice"]
            language = resolved_runtime["language"]
            logger.info(
                "building OpenAI realtime session model=%s voice=%s language=%s instructions_chars=%s instructions_sha256=%s",
                model,
                voice,
                language,
                len(resolved_instructions),
                instruction_fingerprint(resolved_instructions),
            )
            return AgentSession(
                llm=openai.realtime.RealtimeModel(
                    model=model,
                    voice=voice,
                    reasoning=RealtimeReasoning(effort="low"),
                    input_audio_transcription=AudioTranscription(
                        model="gpt-realtime-whisper",
                        language=language,
                    ),
                    turn_detection=SemanticVad(
                        type="semantic_vad",
                        eagerness="medium",
                        create_response=True,
                        interrupt_response=True,
                    ),
                )
            )
        raise ValueError(f"Unsupported realtime provider: {provider}")

    from livekit.agents import TurnHandlingOptions
    from livekit.plugins import silero
    from livekit.plugins.turn_detector.multilingual import MultilingualModel

    return AgentSession(
        stt=inference.STT(
            model=os.getenv("VOICE_AGENT_STT_MODEL", "deepgram/nova-3"),
            language=runtime.get("language") or os.getenv("VOICE_AGENT_LANGUAGE", "multi"),
        ),
        llm=inference.LLM(model=os.getenv("VOICE_AGENT_LLM_MODEL", "openai/gpt-4.1-mini")),
        tts=inference.TTS(
            model=os.getenv("VOICE_AGENT_TTS_MODEL", "cartesia/sonic-3"),
            voice=os.getenv("VOICE_AGENT_TTS_VOICE", "9626c31c-bec5-4cca-baa8-f8ba9e84c8bc"),
            language=os.getenv("VOICE_AGENT_TTS_LANGUAGE", "tr"),
        ),
        vad=silero.VAD.load(),
        turn_handling=TurnHandlingOptions(turn_detection=MultilingualModel()),
    )


def extract_message_text(message: ChatMessage) -> str:
    text_content = getattr(message, "text_content", None)
    if text_content:
        return str(text_content).strip()

    content = getattr(message, "content", None)
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        return " ".join(str(item) for item in content if isinstance(item, str)).strip()
    return ""


def role_for_livekit(role: str) -> str:
    if role == "assistant":
        return "ai"
    if role == "user":
        return "caller"
    return "system"


def disconnect_reason_name(reason: Any) -> str:
    try:
        return rtc.DisconnectReason.Name(reason).lower()
    except Exception:
        return str(reason).lower()


def end_reason_for_disconnect(reason: Any) -> str:
    name = disconnect_reason_name(reason)
    if "client_initiated" in name:
        return "caller_disconnected"
    if "user_rejected" in name:
        return "caller_rejected"
    if "user_unavailable" in name:
        return "caller_unavailable"
    if "sip_trunk_failure" in name:
        return "sip_trunk_failure"
    if "room_deleted" in name:
        return "livekit_room_deleted"
    return f"livekit_disconnect_{name}".replace(" ", "_")


def _transcript_segment_id(item: ChatMessage, text: str) -> str | None:
    """Return a stable idempotent key for this transcript segment.

    Prefer the item's own id when available (Gemini realtime items have ids).
    Fall back to a content fingerprint so duplicate events do not create
    duplicate rows on the Rails side.
    """
    item_id = getattr(item, "id", None)
    if item_id:
        return str(item_id)
    return hashlib.sha256(f"{item.role}:{text}".encode("utf-8")).hexdigest()[:16]


def _fire_and_forget(name: str, coro: Any) -> None:
    async def _run() -> None:
        try:
            await coro
        except Exception:
            logger.exception("async task %s failed", name)

    task = asyncio.create_task(_run())
    _BACKGROUND_TASKS.add(task)
    task.add_done_callback(_BACKGROUND_TASKS.discard)


def bind_transcript_events(session: AgentSession, provider_call_id: str, chatwoot: ChatwootClient) -> None:
    @session.on("conversation_item_added")
    def on_conversation_item_added(ev: Any) -> None:
        item = getattr(ev, "item", None)
        if not isinstance(item, ChatMessage):
            return

        text = extract_message_text(item)
        if not text:
            return

        segment_id = _transcript_segment_id(item, text)
        logger.info(
            "transcript segment received room=%s role=%s text_chars=%s segment_id=%s",
            provider_call_id,
            item.role,
            len(text),
            segment_id,
        )
        _fire_and_forget(
            "append_transcript",
            chatwoot.append_transcript(
                provider_call_id,
                role_for_livekit(item.role),
                text,
                "livekit_agent",
                {
                    "livekit_role": item.role,
                    "external_segment_id": segment_id,
                },
            ),
        )


async def entrypoint(ctx: agents.JobContext) -> None:
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    provider_call_id = ctx.room.name
    await _entrypoint_inner(ctx, provider_call_id)


async def _entrypoint_inner(ctx: agents.JobContext, provider_call_id: str) -> None:
    metadata = job_metadata(ctx)
    chatwoot = ChatwootClient()
    try:
        try:
            runtime_context = await chatwoot.agent_context(provider_call_id, metadata)
        except AgentContextRejected as error:
            logger.warning(
                "voice agent context rejected for room=%s status=%s message=%s",
                provider_call_id,
                error.status,
                error.message,
            )
            return

        instructions = str(runtime_context.get("instructions") or "").strip() or session_instructions(metadata)
        voice_agent = runtime_context.get("voice_agent") or {}
        runtime = runtime_context.get("runtime") or {}
        resolved_runtime = resolve_realtime_runtime(runtime)
        realtime_model_name = resolved_runtime["model"] if runtime.get("architecture") == "realtime" else None
        greeting = str(voice_agent.get("greeting") or "").strip() or None
        tools = build_chatwoot_tools(runtime_context, chatwoot, provider_call_id)
        try:
            participant = await wait_for_customer_participant(ctx)
        except asyncio.TimeoutError:
            await chatwoot.end_call(provider_call_id, "participant_timeout")
            return
        await chatwoot.record_event(
            provider_call_id,
            "agent_listening",
            {"participant_identity": participant.identity},
        )

        ended = False

        async def end_call_once(reason: str) -> None:
            nonlocal ended
            if ended:
                return
            ended = True
            await chatwoot.end_call(provider_call_id, reason)

        @ctx.room.on("participant_disconnected")
        def on_participant_disconnected(
            disconnected_participant: rtc.RemoteParticipant,
        ) -> None:
            if disconnected_participant.identity != participant.identity:
                return

            reason = end_reason_for_disconnect(disconnected_participant.disconnect_reason)
            _fire_and_forget("participant_disconnected_end_call", end_call_once(reason))

        session = build_session(instructions=instructions, runtime=runtime)
        bind_transcript_events(session, provider_call_id, chatwoot)

        async def on_shutdown(reason: str) -> None:
            logger.info(
                "shutdown signal received for room=%s reason=%s",
                provider_call_id,
                reason,
            )
            await chatwoot.record_event(provider_call_id, "agent_session_ended", {"reason": reason})
            await end_call_once("livekit_dispatch_cancelled")

        ctx.add_shutdown_callback(on_shutdown)

        await session.start(
            room=ctx.room,
            agent=VoiceAssistant(
                provider_call_id=provider_call_id,
                instructions=instructions,
                greeting=greeting,
                tools=tools,
                language=resolved_runtime["language"],
                realtime_provider=resolved_runtime["provider"] if realtime_model_name else None,
                realtime_model_name=realtime_model_name,
            ),
            room_input_options=RoomInputOptions(participant_identity=participant.identity),
        )
    finally:
        await chatwoot.close()


_BACKGROUND_TASKS: set[asyncio.Task] = set()


def worker_max_concurrent_jobs() -> int:
    value = int(os.getenv("VOICE_AGENT_MAX_CONCURRENT_JOBS", "10"))
    if value < 1:
        raise ValueError("VOICE_AGENT_MAX_CONCURRENT_JOBS must be at least 1")
    return value


def worker_load(server: agents.AgentServer) -> float:
    return min(len(server.active_jobs) / worker_max_concurrent_jobs(), 1.0)


def build_worker_options() -> agents.WorkerOptions:
    options: dict[str, Any] = {
        "entrypoint_fnc": entrypoint,
        "agent_name": os.getenv("VOICE_AGENT_NAME", "kozmopath-voice-agent"),
        "load_fnc": worker_load,
        "load_threshold": 0.95,
        "host": "0.0.0.0",
        "port": int(os.getenv("VOICE_AGENT_HEALTH_PORT", "9090")),
        "drain_timeout": int(os.getenv("VOICE_AGENT_DRAIN_TIMEOUT_SECONDS", "1200")),
    }
    prometheus_port = os.getenv("VOICE_AGENT_PROMETHEUS_PORT")
    if prometheus_port:
        options["prometheus_port"] = int(prometheus_port)

    return agents.WorkerOptions(**options)


if __name__ == "__main__":
    agents.cli.run_app(build_worker_options())
