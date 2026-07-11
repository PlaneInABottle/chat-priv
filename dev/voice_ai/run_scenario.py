#!/usr/bin/env python3
"""Run one deterministic, end-to-end Voice AI scenario against Chatwoot."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import time
import uuid
import wave
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import aiohttp
from livekit import rtc


FRAME_DURATION_MS = 20
DEFAULT_BASE_URL = "http://localhost:3000"
DEFAULT_TIMEOUT_SECONDS = 45.0
DEFAULT_SILENCE_SECONDS = 2.0
DEFAULT_READY_DELAY_SECONDS = 0.5


class HarnessError(RuntimeError):
    """Raised when the scenario cannot complete or its assertions fail."""


@dataclass(frozen=True)
class WavFixture:
    sample_rate: int
    frames: tuple[bytes, ...]
    duration_seconds: float


@dataclass
class AudioCapture:
    output_path: Path
    first_frame_at: float | None = None
    frame_count: int = 0
    sample_count: int = 0
    error: str | None = None
    tasks: list[asyncio.Task[None]] = field(default_factory=list)


@dataclass(frozen=True)
class Assertions:
    caller_text: str | None
    ai_text: str | None
    tools: tuple[str, ...]
    require_caller_transcript: bool
    require_ai_transcript: bool
    require_agent_audio: bool


@dataclass(frozen=True)
class ScenarioConfig:
    account_id: int
    inbox_id: int
    voice_agent_id: int
    wav_path: Path
    response_wav_path: Path
    timeout_seconds: float
    silence_seconds: float
    ready_delay_seconds: float
    caller_name: str
    caller_number: str
    assertions: Assertions


def load_wav_fixture(path: Path) -> WavFixture:
    if not path.is_file():
        raise HarnessError(f"WAV fixture does not exist: {path}")

    try:
        with wave.open(str(path), "rb") as wav_file:
            channels = wav_file.getnchannels()
            sample_width = wav_file.getsampwidth()
            sample_rate = wav_file.getframerate()
            total_samples = wav_file.getnframes()
            pcm = wav_file.readframes(total_samples)
    except (wave.Error, EOFError) as error:
        raise HarnessError(f"Invalid WAV fixture: {error}") from error

    if channels != 1 or sample_width != 2:
        raise HarnessError("WAV fixture must be mono, 16-bit PCM audio")
    if sample_rate <= 0 or sample_rate * FRAME_DURATION_MS % 1000:
        raise HarnessError("WAV sample rate must support exact 20 ms frames")

    bytes_per_frame = sample_rate * FRAME_DURATION_MS // 1000 * sample_width
    frames = tuple(
        pcm[offset : offset + bytes_per_frame]
        for offset in range(0, len(pcm), bytes_per_frame)
        if pcm[offset : offset + bytes_per_frame]
    )
    if not frames:
        raise HarnessError("WAV fixture contains no audio frames")

    return WavFixture(
        sample_rate=sample_rate,
        frames=frames,
        duration_seconds=total_samples / sample_rate,
    )


def transcript_text(call: dict[str, Any], role: str) -> str:
    return " ".join(
        segment.get("text", "")
        for segment in call.get("transcript_segments", [])
        if segment.get("role") == role
    ).strip()


def ai_reply_text(call: dict[str, Any]) -> str:
    segments = call.get("transcript_segments", [])
    first_caller_index = next(
        (
            index
            for index, segment in enumerate(segments)
            if segment.get("role") == "caller"
        ),
        None,
    )
    if first_caller_index is None:
        return ""
    return " ".join(
        segment.get("text", "")
        for segment in segments[first_caller_index + 1 :]
        if segment.get("role") == "ai"
    ).strip()


def assertion_failures(call: dict[str, Any], expected: Assertions) -> list[str]:
    caller_text = transcript_text(call, "caller")
    ai_text = ai_reply_text(call)
    tool_events = call.get("tool_events", [])
    executed_tools = Counter(
        event.get("tool") for event in tool_events if event.get("status") == "executed"
    )

    failures = []
    if expected.require_caller_transcript and not caller_text:
        failures.append("caller transcript is missing")
    if expected.require_ai_transcript and not ai_text:
        failures.append("AI transcript after the caller turn is missing")
    if (
        expected.caller_text
        and expected.caller_text.casefold() not in caller_text.casefold()
    ):
        failures.append(f"caller transcript does not contain {expected.caller_text!r}")
    if expected.ai_text and expected.ai_text.casefold() not in ai_text.casefold():
        failures.append(f"AI transcript does not contain {expected.ai_text!r}")
    for tool, expected_count in Counter(expected.tools).items():
        actual_count = executed_tools[tool]
        if actual_count != expected_count:
            failures.append(
                f"executed tool {tool!r} expected {expected_count} time(s), got {actual_count}"
            )
        failed_count = sum(
            event.get("tool") == tool and event.get("status") != "executed"
            for event in tool_events
        )
        if failed_count:
            failures.append(f"tool {tool!r} has {failed_count} non-executed event(s)")
    return failures


class ChatwootClient:
    def __init__(self, base_url: str, email: str | None, password: str | None):
        self.base_url = base_url.rstrip("/")
        self.email = email
        self.password = password
        self.auth_headers = self._auth_headers_from_environment()
        self.session = aiohttp.ClientSession()

    async def close(self) -> None:
        await self.session.close()

    async def authenticate(self) -> None:
        if self.auth_headers:
            return
        if not self.email or not self.password:
            raise HarnessError(
                "Set CHATWOOT_TEST_EMAIL and CHATWOOT_TEST_PASSWORD, or provide "
                "CHATWOOT_ACCESS_TOKEN, CHATWOOT_CLIENT, and CHATWOOT_UID"
            )

        await self._request(
            "POST",
            "/auth/sign_in",
            json={"email": self.email, "password": self.password},
            authenticated=False,
        )
        if not self.auth_headers:
            raise HarnessError("Chatwoot sign-in did not return authentication headers")

    async def create_test_call(self, config: ScenarioConfig) -> dict[str, Any]:
        return await self._request(
            "POST",
            f"/api/v1/accounts/{config.account_id}/voice/test_calls",
            json={
                "inbox_id": config.inbox_id,
                "voice_agent_id": config.voice_agent_id,
                "caller_name": config.caller_name,
                "caller_number": config.caller_number,
            },
        )

    async def caller_token(self, account_id: int, call_id: int) -> dict[str, Any]:
        return await self._request(
            "POST",
            f"/api/v1/accounts/{account_id}/voice/calls/{call_id}/token",
            json={
                "participant_type": "caller",
                "client_session_id": f"voice-harness-{uuid.uuid4().hex}",
            },
        )

    async def get_call(self, account_id: int, call_id: int) -> dict[str, Any]:
        return await self._request(
            "GET", f"/api/v1/accounts/{account_id}/voice/calls/{call_id}"
        )

    async def end_call(self, account_id: int, call_id: int) -> dict[str, Any]:
        return await self._request(
            "POST",
            f"/api/v1/accounts/{account_id}/voice/calls/{call_id}/end",
            json={"end_reason": "deterministic_test_ended"},
        )

    async def _request(
        self,
        method: str,
        path: str,
        *,
        json: dict[str, Any] | None = None,
        authenticated: bool = True,
    ) -> dict[str, Any]:
        headers = self.auth_headers if authenticated else {}
        async with self.session.request(
            method, f"{self.base_url}{path}", json=json, headers=headers
        ) as response:
            payload = await self._response_payload(response)
            self._update_auth_headers(response.headers)
            if response.status >= 400:
                detail = payload.get("error") if isinstance(payload, dict) else payload
                raise HarnessError(
                    f"{method} {path} returned {response.status}: {detail}"
                )
            if not isinstance(payload, dict):
                raise HarnessError(f"{method} {path} did not return a JSON object")
            return payload

    async def _response_payload(self, response: aiohttp.ClientResponse) -> Any:
        try:
            return await response.json(content_type=None)
        except (json.JSONDecodeError, aiohttp.ContentTypeError):
            return (await response.text()).strip()

    def _update_auth_headers(self, headers: aiohttp.typedefs.LooseHeaders) -> None:
        access_token = headers.get("access-token")
        client = headers.get("client")
        uid = headers.get("uid")
        if access_token and client and uid:
            self.auth_headers = {
                "access-token": access_token,
                "client": client,
                "uid": uid,
            }

    def _auth_headers_from_environment(self) -> dict[str, str]:
        values = {
            "access-token": os.getenv("CHATWOOT_ACCESS_TOKEN", ""),
            "client": os.getenv("CHATWOOT_CLIENT", ""),
            "uid": os.getenv("CHATWOOT_UID", ""),
        }
        return values if all(values.values()) else {}


async def record_remote_audio(track: rtc.Track, capture: AudioCapture) -> None:
    capture.output_path.parent.mkdir(parents=True, exist_ok=True)
    stream = rtc.AudioStream(track, sample_rate=48_000, num_channels=1)
    try:
        with wave.open(str(capture.output_path), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(48_000)
            async for event in stream:
                if capture.first_frame_at is None:
                    capture.first_frame_at = time.monotonic()
                output.writeframesraw(bytes(event.frame.data))
                capture.frame_count += 1
                capture.sample_count += event.frame.samples_per_channel
    except Exception as error:  # LiveKit surfaces media stream failures asynchronously.
        capture.error = str(error)
    finally:
        await stream.aclose()


def attach_remote_audio_capture(room: rtc.Room, capture: AudioCapture) -> None:
    def on_track_subscribed(
        track: rtc.Track,
        _publication: rtc.RemoteTrackPublication,
        _participant: rtc.RemoteParticipant,
    ) -> None:
        if track.kind != rtc.TrackKind.KIND_AUDIO or capture.tasks:
            return
        capture.tasks.append(asyncio.create_task(record_remote_audio(track, capture)))

    room.on("track_subscribed", on_track_subscribed)


async def finish_remote_audio_capture(capture: AudioCapture) -> None:
    if not capture.tasks:
        return
    try:
        await asyncio.wait_for(
            asyncio.gather(*capture.tasks, return_exceptions=True), timeout=2.0
        )
    except TimeoutError:
        for task in capture.tasks:
            task.cancel()
        await asyncio.gather(*capture.tasks, return_exceptions=True)
    if capture.frame_count == 0:
        capture.output_path.unlink(missing_ok=True)


async def publish_fixture(
    room: rtc.Room, fixture: WavFixture, silence_seconds: float
) -> float:
    source = rtc.AudioSource(fixture.sample_rate, 1, queue_size_ms=1_000)
    track = rtc.LocalAudioTrack.create_audio_track("deterministic-caller", source)
    options = rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE)
    publication = await room.local_participant.publish_track(track, options)

    try:
        for pcm in fixture.frames:
            await source.capture_frame(
                rtc.AudioFrame(
                    data=pcm,
                    sample_rate=fixture.sample_rate,
                    num_channels=1,
                    samples_per_channel=len(pcm) // 2,
                )
            )

        silence_frame_count = round(silence_seconds * 1000 / FRAME_DURATION_MS)
        samples_per_frame = fixture.sample_rate * FRAME_DURATION_MS // 1000
        silence = bytes(samples_per_frame * 2)
        for _ in range(silence_frame_count):
            await source.capture_frame(
                rtc.AudioFrame(
                    data=silence,
                    sample_rate=fixture.sample_rate,
                    num_channels=1,
                    samples_per_channel=samples_per_frame,
                )
            )
        await source.wait_for_playout()
        return time.monotonic()
    finally:
        await room.local_participant.unpublish_track(publication.sid)
        await source.aclose()


async def wait_for_outcome(
    client: ChatwootClient,
    config: ScenarioConfig,
    call_id: int,
    capture: AudioCapture,
) -> dict[str, Any]:
    deadline = time.monotonic() + config.timeout_seconds
    last_call: dict[str, Any] = {}
    last_failures: list[str] = []

    while time.monotonic() < deadline:
        if capture.error:
            raise HarnessError(f"Agent audio capture failed: {capture.error}")
        last_call = await client.get_call(config.account_id, call_id)
        last_failures = assertion_failures(last_call, config.assertions)
        if config.assertions.require_agent_audio and capture.frame_count == 0:
            last_failures.append("agent audio is missing")
        if not last_failures:
            return last_call
        await asyncio.sleep(0.5)

    details = "; ".join(last_failures) or "no call state was returned"
    raise HarnessError(
        f"Scenario timed out after {config.timeout_seconds:g}s: {details}"
    )


async def wait_for_agent_ready(
    client: ChatwootClient, config: ScenarioConfig, call_id: int
) -> float:
    started_at = time.monotonic()
    deadline = started_at + min(config.timeout_seconds, 20.0)
    last_status = "unknown"

    while time.monotonic() < deadline:
        call = await client.get_call(config.account_id, call_id)
        last_status = str(call.get("ai_status") or "unknown")
        if last_status == "active":
            await asyncio.sleep(config.ready_delay_seconds)
            return time.monotonic()
        if call.get("status") in {"completed", "failed", "no-answer", "canceled"}:
            raise HarnessError(
                f"Call became terminal before the voice agent was ready: {call.get('status')}"
            )
        await asyncio.sleep(0.25)

    raise HarnessError(
        f"Voice agent did not become ready; last status was {last_status}"
    )


def validate_created_call(call: dict[str, Any], config: ScenarioConfig) -> int:
    if not call.get("test_call"):
        raise HarnessError("Chatwoot did not create an isolated test call")
    if call.get("conversation_id") is not None:
        raise HarnessError("Test call unexpectedly created a customer conversation")
    if int(call.get("voice_agent_id", 0)) != config.voice_agent_id:
        raise HarnessError("Test call was dispatched to a different voice agent")
    try:
        return int(call["id"])
    except (KeyError, TypeError, ValueError) as error:
        raise HarnessError(
            "Test call response did not include a valid call id"
        ) from error


async def run_scenario(config: ScenarioConfig, base_url: str) -> dict[str, Any]:
    fixture = load_wav_fixture(config.wav_path)
    config.response_wav_path.unlink(missing_ok=True)
    client = ChatwootClient(
        base_url=base_url,
        email=os.getenv("CHATWOOT_TEST_EMAIL"),
        password=os.getenv("CHATWOOT_TEST_PASSWORD"),
    )
    room = rtc.Room()
    capture = AudioCapture(output_path=config.response_wav_path)
    attach_remote_audio_capture(room, capture)
    call_id: int | None = None
    room_connected_at: float | None = None
    agent_ready_at: float | None = None
    verified_call: dict[str, Any] | None = None
    ended_call: dict[str, Any] | None = None

    try:
        await client.authenticate()
        created_call = await client.create_test_call(config)
        call_id = validate_created_call(created_call, config)
        token = await client.caller_token(config.account_id, call_id)
        await room.connect(token["url"], token["token"])
        room_connected_at = time.monotonic()

        agent_ready_at = await wait_for_agent_ready(client, config, call_id)
        await publish_fixture(room, fixture, config.silence_seconds)
        verified_call = await wait_for_outcome(client, config, call_id, capture)
    finally:
        try:
            if room.connection_state != rtc.ConnectionState.CONN_DISCONNECTED:
                await room.disconnect()
        except Exception as error:
            print(
                f"warning: could not disconnect LiveKit room: {error}", file=sys.stderr
            )
        try:
            await finish_remote_audio_capture(capture)
        finally:
            if call_id is not None:
                try:
                    ended_call = await client.end_call(config.account_id, call_id)
                except (HarnessError, aiohttp.ClientError) as error:
                    print(
                        f"warning: could not end call {call_id}: {error}",
                        file=sys.stderr,
                    )
            await client.close()

    if verified_call is None or ended_call is None or call_id is None:
        raise HarnessError("Scenario ended without a verified call result")

    return build_result(
        call_id=call_id,
        verified_call=verified_call,
        ended_call=ended_call,
        fixture=fixture,
        capture=capture,
        room_connected_at=room_connected_at,
        agent_ready_at=agent_ready_at,
    )


def build_result(
    *,
    call_id: int,
    verified_call: dict[str, Any],
    ended_call: dict[str, Any],
    fixture: WavFixture,
    capture: AudioCapture,
    room_connected_at: float | None,
    agent_ready_at: float | None,
) -> dict[str, Any]:
    first_audio_ms = None
    if room_connected_at is not None and capture.first_frame_at is not None:
        first_audio_ms = round((capture.first_frame_at - room_connected_at) * 1000)
    ready_ms = None
    if room_connected_at is not None and agent_ready_at is not None:
        ready_ms = round((agent_ready_at - room_connected_at) * 1000)

    return {
        "ok": True,
        "call_id": call_id,
        "status": ended_call.get("status"),
        "end_reason": ended_call.get("end_reason"),
        "input_audio_seconds": round(fixture.duration_seconds, 3),
        "agent_ready_ms": ready_ms,
        "room_to_first_agent_audio_ms": first_audio_ms,
        "agent_audio_seconds": round(capture.sample_count / 48_000, 3),
        "agent_audio_path": str(capture.output_path) if capture.frame_count else None,
        "caller_transcript": transcript_text(verified_call, "caller"),
        "ai_transcript": transcript_text(verified_call, "ai"),
        "ai_reply_transcript": ai_reply_text(verified_call),
        "tool_events": [
            {
                "tool": event.get("tool"),
                "status": event.get("status"),
                "duration_ms": event.get("duration_ms"),
            }
            for event in verified_call.get("tool_events", [])
        ],
    }


def parse_args(
    argv: list[str] | None = None,
) -> tuple[argparse.Namespace, ScenarioConfig]:
    parser = argparse.ArgumentParser(
        description="Publish one finite WAV fixture through a real Chatwoot Voice AI test call."
    )
    parser.add_argument(
        "--base-url", default=os.getenv("CHATWOOT_BASE_URL", DEFAULT_BASE_URL)
    )
    parser.add_argument(
        "--account-id", type=int, default=os.getenv("VOICE_TEST_ACCOUNT_ID")
    )
    parser.add_argument(
        "--inbox-id", type=int, default=os.getenv("VOICE_TEST_INBOX_ID")
    )
    parser.add_argument(
        "--voice-agent-id", type=int, default=os.getenv("VOICE_TEST_VOICE_AGENT_ID")
    )
    parser.add_argument("--wav", type=Path, required=True)
    parser.add_argument("--response-wav", type=Path)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    parser.add_argument("--silence", type=float, default=DEFAULT_SILENCE_SECONDS)
    parser.add_argument(
        "--ready-delay", type=float, default=DEFAULT_READY_DELAY_SECONDS
    )
    parser.add_argument("--caller-name", default="Deterministic voice test")
    parser.add_argument("--caller-number", default="+900000000001")
    parser.add_argument("--expect-caller-text")
    parser.add_argument("--expect-ai-text")
    parser.add_argument("--expect-tool", action="append", default=[])
    parser.add_argument("--allow-no-caller-transcript", action="store_true")
    parser.add_argument("--allow-no-ai-reply", action="store_true")
    parser.add_argument("--allow-no-agent-audio", action="store_true")
    args = parser.parse_args(argv)

    missing = [
        name
        for name, value in (
            ("--account-id", args.account_id),
            ("--inbox-id", args.inbox_id),
            ("--voice-agent-id", args.voice_agent_id),
        )
        if value is None
    ]
    if missing:
        parser.error(f"required arguments are missing: {', '.join(missing)}")
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    if args.silence < 0:
        parser.error("--silence cannot be negative")
    if args.ready_delay < 0:
        parser.error("--ready-delay cannot be negative")

    response_wav = args.response_wav or Path(
        f"/tmp/chatwoot-voice-ai/response-{uuid.uuid4().hex[:12]}.wav"
    )
    config = ScenarioConfig(
        account_id=args.account_id,
        inbox_id=args.inbox_id,
        voice_agent_id=args.voice_agent_id,
        wav_path=args.wav.expanduser().resolve(),
        response_wav_path=response_wav.expanduser().resolve(),
        timeout_seconds=args.timeout,
        silence_seconds=args.silence,
        ready_delay_seconds=args.ready_delay,
        caller_name=args.caller_name,
        caller_number=args.caller_number,
        assertions=Assertions(
            caller_text=args.expect_caller_text,
            ai_text=args.expect_ai_text,
            tools=tuple(args.expect_tool),
            require_caller_transcript=not args.allow_no_caller_transcript,
            require_ai_transcript=not args.allow_no_ai_reply,
            require_agent_audio=not args.allow_no_agent_audio,
        ),
    )
    return args, config


def main(argv: list[str] | None = None) -> int:
    args, config = parse_args(argv)
    try:
        result = asyncio.run(run_scenario(config, args.base_url))
    except (HarnessError, aiohttp.ClientError, KeyError) as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=True))
        return 1
    print(json.dumps(result, ensure_ascii=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
