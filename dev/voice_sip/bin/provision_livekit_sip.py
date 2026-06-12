#!/usr/bin/env python3
"""Create or reuse a LiveKit inbound SIP trunk and dispatch rule for local Asterisk tests."""

import asyncio
import json
import os
from pathlib import Path
from typing import Any

from livekit import api

REPO_ROOT = Path(__file__).resolve().parents[3]


def required_env(key: str) -> str:
    value = os.getenv(key, "").strip()
    if not value:
        raise RuntimeError(f"{key} is required")
    return value


def env_or_default(key: str, default: str) -> str:
    return os.getenv(key, "").strip() or default


def first_existing(items: list[Any], name: str) -> Any | None:
    return next((item for item in items if getattr(item, "name", None) == name), None)


async def main() -> None:
    phone_number = required_env("VOICE_SIP_PHONE_NUMBER")
    voice_number_id = required_env("VOICE_SIP_VOICE_NUMBER_ID")
    agent_name = os.getenv("VOICE_AGENT_NAME", "kozmopath-voice-agent")
    auth_username = os.getenv("LIVEKIT_SIP_AUTH_USERNAME", "chatwoot-local")
    auth_password = required_env("LIVEKIT_SIP_AUTH_PASSWORD")
    trunk_name = env_or_default("LIVEKIT_SIP_TRUNK_NAME", f"Chatwoot local Asterisk {phone_number}")
    dispatch_name = env_or_default("LIVEKIT_SIP_DISPATCH_NAME", f"Chatwoot local dispatch {phone_number}")
    room_prefix = env_or_default("LIVEKIT_SIP_ROOM_PREFIX", "local-sip-")

    livekit_api = api.LiveKitAPI()
    try:
        trunk = await find_or_create_trunk(
            livekit_api=livekit_api,
            name=trunk_name,
            phone_number=phone_number,
            auth_username=auth_username,
            auth_password=auth_password,
        )
        dispatch = await find_or_create_dispatch(
            livekit_api=livekit_api,
            name=dispatch_name,
            trunk_id=trunk.sip_trunk_id,
            room_prefix=room_prefix,
            agent_name=agent_name,
            metadata={
                "voice_number_id": int(voice_number_id),
                "phone_number": phone_number,
                "to_number": phone_number,
                "livekit_inbound_trunk_id": trunk.sip_trunk_id,
            },
        )
    finally:
        await livekit_api.aclose()

    result = {
        "phone_number": phone_number,
        "voice_number_id": int(voice_number_id),
        "livekit_inbound_trunk_id": trunk.sip_trunk_id,
        "livekit_dispatch_rule_id": dispatch.sip_dispatch_rule_id,
        "trunk_name": trunk.name,
        "dispatch_name": dispatch.name,
    }
    output_path = REPO_ROOT / "dev/voice_sip/.generated/livekit_sip.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    print("\nExport these before re-running provision_chatwoot_number.rb:")
    print(f"export LIVEKIT_SIP_INBOUND_TRUNK_ID={trunk.sip_trunk_id}")
    print(f"export LIVEKIT_SIP_DISPATCH_RULE_ID={dispatch.sip_dispatch_rule_id}")


async def find_or_create_trunk(
    *,
    livekit_api: api.LiveKitAPI,
    name: str,
    phone_number: str,
    auth_username: str,
    auth_password: str,
) -> Any:
    existing = await livekit_api.sip.list_inbound_trunk(api.ListSIPInboundTrunkRequest())
    trunk = first_existing(list(existing.items), name)
    if trunk:
        return trunk

    request = api.CreateSIPInboundTrunkRequest(
        trunk=api.SIPInboundTrunkInfo(
            name=name,
            numbers=[phone_number],
            auth_username=auth_username,
            auth_password=auth_password,
        )
    )
    return await livekit_api.sip.create_inbound_trunk(request)


async def find_or_create_dispatch(
    *,
    livekit_api: api.LiveKitAPI,
    name: str,
    trunk_id: str,
    room_prefix: str,
    agent_name: str,
    metadata: dict[str, Any],
) -> Any:
    existing = await livekit_api.sip.list_dispatch_rule(api.ListSIPDispatchRuleRequest())
    dispatch = first_existing(list(existing.items), name)
    if dispatch:
        return dispatch

    rule = api.SIPDispatchRule(
        dispatch_rule_individual=api.SIPDispatchRuleIndividual(room_prefix=room_prefix)
    )
    request = api.CreateSIPDispatchRuleRequest(
        dispatch_rule=api.SIPDispatchRuleInfo(
            name=name,
            rule=rule,
            trunk_ids=[trunk_id],
            room_config=api.RoomConfiguration(
                agents=[
                    api.RoomAgentDispatch(
                        agent_name=agent_name,
                        metadata=json.dumps(metadata),
                    )
                ]
            ),
        )
    )
    return await livekit_api.sip.create_dispatch_rule(request)


if __name__ == "__main__":
    asyncio.run(main())
