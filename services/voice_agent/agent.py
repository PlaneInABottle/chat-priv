import asyncio
import hashlib
import json
import logging
import os
import time
from typing import Any

import aiohttp
from dotenv import load_dotenv
from livekit import agents, rtc
from livekit.agents import Agent, AgentSession, AutoSubscribe, RoomInputOptions, function_tool, inference
from livekit.agents.llm import ChatMessage
from livekit.plugins import google

load_dotenv()

logger = logging.getLogger("voice_agent")

DEFAULT_BASE_INSTRUCTIONS = (
    "You are Kozmopath's Turkish customer support voice assistant. "
    "Speak only in natural Istanbul Turkish unless the caller explicitly asks for another language. "
    "Use clear Turkish pronunciation, short sentences, and a calm professional support tone. "
    "Do not mix English into Turkish answers unless a product name, brand, or technical term requires it. "
    "Avoid long lists on voice calls; ask one short clarification question when needed. "
    "If the caller asks for a human, call request_human_handoff."
)
DEFAULT_REALTIME_MODEL = "gemini-3.1-flash-live-preview"


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

    async def request_handoff(self, provider_call_id: str, reason: str) -> dict[str, Any]:
        return await self.post(f"/internal/voice/calls/{provider_call_id}/handoff", {"reason": reason})

    async def end_call(self, provider_call_id: str, end_reason: str) -> dict[str, Any]:
        return await self.post(f"/internal/voice/calls/{provider_call_id}/end", {"end_reason": end_reason})

    async def record_tool_call(
        self,
        provider_call_id: str,
        tool: str,
        status: str,
        arguments: dict[str, Any],
        result: dict[str, Any],
        error_message: str | None,
        duration_ms: int,
    ) -> dict[str, Any]:
        return await self.post(
            f"/internal/voice/calls/{provider_call_id}/tool_call",
            {
                "tool": tool,
                "status": status,
                "arguments": arguments,
                "result": result,
                "error_message": error_message,
                "duration_ms": duration_ms,
            },
        )

    async def append_transcript(self, provider_call_id: str, role: str, text: str, source: str, metadata: dict[str, Any]) -> dict[str, Any]:
        payload = {"role": role, "text": text, "source": source, "metadata": metadata}
        external_id = metadata.get("external_segment_id")
        if external_id:
            payload["external_segment_id"] = external_id
        return await self.post(
            f"/internal/voice/calls/{provider_call_id}/transcript",
            payload,
        )


class VoiceAssistant(Agent):
    def __init__(self, provider_call_id: str, instructions: str, greeting: str | None = None, end_once: Any = None, chatwoot: ChatwootClient | None = None) -> None:
        self.provider_call_id = provider_call_id
        self.chatwoot = chatwoot or ChatwootClient()
        self.greeting = greeting
        self.end_once = end_once
        super().__init__(instructions=instructions)

    @function_tool
    async def request_human_handoff(self, reason: str) -> str:
        """Request handoff to a human Chatwoot agent."""
        await self.execute_chatwoot_tool(
            "request_human_handoff",
            {"reason": reason},
            lambda: self.chatwoot.request_handoff(self.provider_call_id, reason),
        )
        return "Human handoff requested."

    @function_tool
    async def end_customer_call(self, reason: str) -> str:
        """End the call when the conversation is complete."""
        if self.end_once:
            operation = lambda: self.end_once(reason)
        else:
            operation = lambda: self.chatwoot.end_call(self.provider_call_id, reason)
        await self.execute_chatwoot_tool(
            "end_customer_call",
            {"reason": reason},
            operation,
        )
        return "Call ended."

    async def execute_chatwoot_tool(self, tool: str, arguments: dict[str, Any], operation: Any) -> dict[str, Any]:
        started_at = time.monotonic()
        try:
            result = await operation()
            await self.safe_record_tool_call(tool, "executed", arguments, compact_tool_result(tool, result), None, started_at)
            return result
        except Exception as exc:
            await self.safe_record_tool_call(tool, "error", arguments, {}, str(exc), started_at)
            raise

    async def safe_record_tool_call(
        self,
        tool: str,
        status: str,
        arguments: dict[str, Any],
        result: dict[str, Any],
        error_message: str | None,
        started_at: float,
    ) -> None:
        try:
            await self.chatwoot.record_tool_call(
                self.provider_call_id,
                tool,
                status,
                arguments,
                result,
                error_message,
                round((time.monotonic() - started_at) * 1000),
            )
        except Exception as exc:
            logger.warning("failed to record voice tool call tool=%s error=%s", tool, exc)

    async def on_enter(self) -> None:
        if gemini_31_realtime_enabled():
            return

        greeting = self.greeting or "Merhaba, size nasil yardimci olabilirim?"
        await self.session.generate_reply(instructions=f"Greet the caller in Turkish with this greeting: {greeting}")


def base_instructions() -> str:
    return os.getenv("VOICE_AGENT_INSTRUCTIONS", DEFAULT_BASE_INSTRUCTIONS)


def realtime_model() -> str:
    return os.getenv("VOICE_AGENT_REALTIME_MODEL", DEFAULT_REALTIME_MODEL)


def realtime_voice() -> str:
    return os.getenv("VOICE_AGENT_GEMINI_VOICE", "Charon")


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


async def wait_for_customer_participant(ctx: agents.JobContext) -> rtc.RemoteParticipant:
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


def build_session(instructions: str | None = None) -> AgentSession:
    resolved_instructions = instructions or base_instructions()
    architecture = voice_agent_architecture()
    if architecture == "realtime":
        provider = os.getenv("VOICE_AGENT_REALTIME_PROVIDER", "gemini")
        if provider == "gemini":
            logger.info(
                "building Gemini realtime session model=%s voice=%s instructions_chars=%s instructions_sha256=%s",
                realtime_model(),
                realtime_voice(),
                len(resolved_instructions),
                instruction_fingerprint(resolved_instructions),
            )
            return AgentSession(
                llm=google.realtime.RealtimeModel(
                    model=realtime_model(),
                    voice=realtime_voice(),
                    temperature=float(os.getenv("VOICE_AGENT_TEMPERATURE", "0.8")),
                    instructions=resolved_instructions,
                )
            )
        raise ValueError(f"Unsupported realtime provider: {provider}")

    from livekit.agents import TurnHandlingOptions
    from livekit.plugins import silero
    from livekit.plugins.turn_detector.multilingual import MultilingualModel

    return AgentSession(
        stt=inference.STT(model=os.getenv("VOICE_AGENT_STT_MODEL", "deepgram/nova-3"), language=os.getenv("VOICE_AGENT_LANGUAGE", "multi")),
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
        asyncio.create_task(
            chatwoot.append_transcript(
                provider_call_id,
                role_for_livekit(item.role),
                text,
                "livekit_agent",
                {
                    "livekit_role": item.role,
                    "external_segment_id": segment_id,
                },
            )
        )


async def entrypoint(ctx: agents.JobContext) -> None:
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    provider_call_id = ctx.room.name
    metadata = job_metadata(ctx)
    instructions = session_instructions(metadata)
    greeting = str(metadata.get("voice_greeting") or "").strip() or None
    chatwoot = ChatwootClient()
    try:
        participant = await wait_for_customer_participant(ctx)
    except asyncio.TimeoutError:
        await chatwoot.end_call(provider_call_id, "participant_timeout")
        return

    ended = False

    async def end_call_once(reason: str) -> None:
        nonlocal ended
        if ended:
            return
        ended = True
        await chatwoot.end_call(provider_call_id, reason)

    @ctx.room.on("participant_disconnected")
    def on_participant_disconnected(disconnected_participant: rtc.RemoteParticipant) -> None:
        if disconnected_participant.identity != participant.identity:
            return

        reason = end_reason_for_disconnect(disconnected_participant.disconnect_reason)
        asyncio.create_task(end_call_once(reason))

    session = build_session(instructions=instructions)
    bind_transcript_events(session, provider_call_id, chatwoot)

    @ctx.shutdown
    def on_shutdown() -> None:
        logger.info("shutdown signal received for room=%s", provider_call_id)
        asyncio.create_task(end_call_once("livekit_dispatch_cancelled"))

    try:
        await session.start(
            room=ctx.room,
            agent=VoiceAssistant(
                provider_call_id=provider_call_id,
                instructions=instructions,
                greeting=greeting,
                end_once=end_call_once,
                chatwoot=chatwoot,
            ),
            room_input_options=RoomInputOptions(participant_identity=participant.identity),
        )
    finally:
        await chatwoot.close()


if __name__ == "__main__":
    agents.cli.run_app(
        agents.WorkerOptions(
            entrypoint_fnc=entrypoint,
            agent_name=os.getenv("VOICE_AGENT_NAME", "kozmopath-voice-agent"),
        )
    )
