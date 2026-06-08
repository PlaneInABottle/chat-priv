import asyncio
import os
from typing import Any

import aiohttp
from dotenv import load_dotenv
from livekit import agents, rtc
from livekit.agents import Agent, AgentSession, AutoSubscribe, function_tool, inference
from livekit.agents.llm import ChatMessage
from livekit.plugins import google

load_dotenv()


class ChatwootClient:
    def __init__(self) -> None:
        self.base_url = os.environ["CHATWOOT_INTERNAL_API_URL"].rstrip("/")
        self.token = os.environ["VOICE_AGENT_INTERNAL_TOKEN"]

    async def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        headers = {"X-Voice-Agent-Token": self.token}
        async with aiohttp.ClientSession(headers=headers) as session:
            async with session.post(f"{self.base_url}{path}", json=payload) as response:
                response.raise_for_status()
                return await response.json()

    async def request_handoff(self, provider_call_id: str, reason: str) -> dict[str, Any]:
        return await self.post(f"/internal/voice/calls/{provider_call_id}/handoff", {"reason": reason})

    async def end_call(self, provider_call_id: str, end_reason: str) -> dict[str, Any]:
        return await self.post(f"/internal/voice/calls/{provider_call_id}/end", {"end_reason": end_reason})

    async def append_transcript(self, provider_call_id: str, role: str, text: str, source: str, metadata: dict[str, Any]) -> dict[str, Any]:
        return await self.post(
            f"/internal/voice/calls/{provider_call_id}/transcript",
            {"role": role, "text": text, "source": source, "metadata": metadata},
        )


class VoiceAssistant(Agent):
    def __init__(self, provider_call_id: str) -> None:
        self.provider_call_id = provider_call_id
        self.chatwoot = ChatwootClient()
        super().__init__(instructions=base_instructions())

    @function_tool
    async def request_human_handoff(self, reason: str) -> str:
        """Request handoff to a human Chatwoot agent."""
        await self.chatwoot.request_handoff(self.provider_call_id, reason)
        return "Human handoff requested."

    @function_tool
    async def end_customer_call(self, reason: str) -> str:
        """End the call when the conversation is complete."""
        await self.chatwoot.end_call(self.provider_call_id, reason)
        return "Call ended."

    async def on_enter(self) -> None:
        if gemini_31_realtime_enabled():
            return

        await self.session.generate_reply(instructions="Greet the caller in Turkish and ask how you can help.")


def base_instructions() -> str:
    return os.getenv(
        "VOICE_AGENT_INSTRUCTIONS",
        (
            "You are a Turkish customer support voice assistant. "
            "Keep answers short, natural, and suitable for a phone call. "
            "If the caller asks for a human, call request_human_handoff."
        ),
    )


def gemini_31_realtime_enabled() -> bool:
    return (
        voice_agent_architecture() == "realtime"
        and os.getenv("VOICE_AGENT_REALTIME_PROVIDER", "gemini") == "gemini"
        and "gemini-3.1" in os.getenv("VOICE_AGENT_REALTIME_MODEL", "")
    )


def voice_agent_architecture() -> str:
    return os.getenv("VOICE_AGENT_ARCHITECTURE") or os.getenv("VOICE_AGENT_MODE", "pipeline")


def participant_wait_timeout() -> float:
    return float(os.getenv("VOICE_AGENT_WAIT_FOR_PARTICIPANT_TIMEOUT_SECONDS", "120"))


def build_session() -> AgentSession:
    architecture = voice_agent_architecture()
    if architecture == "realtime":
        provider = os.getenv("VOICE_AGENT_REALTIME_PROVIDER", "gemini")
        if provider == "gemini":
            return AgentSession(
                llm=google.realtime.RealtimeModel(
                    model=os.getenv("VOICE_AGENT_REALTIME_MODEL", "gemini-2.5-flash-native-audio-preview-12-2025"),
                    voice=os.getenv("VOICE_AGENT_GEMINI_VOICE", "Puck"),
                    temperature=float(os.getenv("VOICE_AGENT_TEMPERATURE", "0.8")),
                    instructions=base_instructions(),
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


def bind_transcript_events(session: AgentSession, provider_call_id: str, chatwoot: ChatwootClient) -> None:
    @session.on("conversation_item_added")
    def on_conversation_item_added(ev: Any) -> None:
        item = getattr(ev, "item", None)
        if not isinstance(item, ChatMessage):
            return

        text = extract_message_text(item)
        if not text:
            return

        asyncio.create_task(
            chatwoot.append_transcript(
                provider_call_id,
                role_for_livekit(item.role),
                text,
                "livekit_agent",
                {"livekit_role": item.role},
            )
        )


async def entrypoint(ctx: agents.JobContext) -> None:
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    provider_call_id = ctx.room.name
    chatwoot = ChatwootClient()
    try:
        await asyncio.wait_for(
            ctx.wait_for_participant(kind=[rtc.ParticipantKind.PARTICIPANT_KIND_STANDARD]),
            timeout=participant_wait_timeout(),
        )
    except asyncio.TimeoutError:
        await chatwoot.end_call(provider_call_id, "participant_timeout")
        return

    session = build_session()
    bind_transcript_events(session, provider_call_id, chatwoot)

    await session.start(room=ctx.room, agent=VoiceAssistant(provider_call_id=provider_call_id))


if __name__ == "__main__":
    agents.cli.run_app(
        agents.WorkerOptions(
            entrypoint_fnc=entrypoint,
            agent_name=os.getenv("VOICE_AGENT_NAME", "kozmopath-voice-agent"),
        )
    )
