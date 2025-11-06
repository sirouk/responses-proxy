#!/usr/bin/env python3
"""
Manual streaming tool-calling example using httpx.

Environment:
  PROXY_URL       (default: http://localhost:8282)
  CHUTES_API_KEY  (required)
"""

import json
import os
from typing import Dict

import httpx

PROXY_URL = os.getenv("PROXY_URL", "http://localhost:8282")
API_KEY = os.getenv("CHUTES_API_KEY")

if not API_KEY:
    raise ValueError("CHUTES_API_KEY environment variable not set")


def stream_response_with_tools() -> None:
    request_data: Dict[str, object] = {
        "model": "gpt-4o-mini",
        "input": "What's the weather in Boston and Seattle? I need both.",
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "get_weather",
                    "description": "Get the current weather in a given location",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "location": {
                                "type": "string",
                                "description": "City and state (e.g. San Francisco, CA)",
                            },
                            "unit": {
                                "type": "string",
                                "enum": ["celsius", "fahrenheit"],
                                "description": "Temperature unit",
                            },
                        },
                        "required": ["location"],
                    },
                },
            }
        ],
        "tool_choice": "auto",
        "parallel_tool_calls": True,
        "stream": True,
    }

    print("🚀 Making request to proxy...")
    print(f"   Model: {request_data['model']}")
    print(f"   Question: {request_data['input']}")

    tool_calls = {}
    text_content = []

    with httpx.stream(
        "POST",
        f"{PROXY_URL}/v1/responses",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {API_KEY}",
        },
        json=request_data,
        timeout=60.0,
    ) as response:
        response.raise_for_status()

        for line in response.iter_lines():
            if not line.startswith("data: "):
                continue

            payload = line[6:]
            if payload == "[DONE]":
                break

            try:
                event = json.loads(payload)
            except json.JSONDecodeError as exc:  # pragma: no cover - manual script
                print(f"⚠️  Failed to parse event: {exc}")
                continue

            event_type = event.get("type", "")

            if event_type == "response.output_text.delta":
                delta = event.get("delta", "")
                text_content.append(delta)
                if delta:
                    print(f"💬 Text: {delta}", end="", flush=True)

            elif event_type == "response.function_call_arguments.delta":
                item_id = event.get("item_id")
                delta = event.get("delta", "")
                if item_id not in tool_calls:
                    tool_calls[item_id] = {"arguments": ""}
                tool_calls[item_id]["arguments"] += delta

            elif event_type == "response.function_call_arguments.done":
                item_id = event.get("item_id")
                if item_id not in tool_calls:
                    tool_calls[item_id] = {}
                tool_calls[item_id]["name"] = event.get("name")
                tool_calls[item_id]["arguments"] = event.get("arguments")

            elif event_type == "response.output_item.done":
                item = event.get("item", {})
                if item.get("type") == "function_call":
                    item_id = item.get("id")
                    if item_id in tool_calls:
                        tool_calls[item_id]["call_id"] = item.get("call_id")

            elif event_type == "response.completed":
                print("\n\n✅ Response completed\n")
                if tool_calls:
                    print(f"🔧 Function calls made: {len(tool_calls)}")
                    for info in tool_calls.values():
                        print(f"   - {info.get('name', 'unknown')} (call_id={info.get('call_id', 'N/A')})")
                        args = info.get("arguments", "{}")
                        try:
                            parsed_args = json.loads(args)
                            print(json.dumps(parsed_args, indent=4))
                        except Exception:  # pragma: no cover - manual script
                            print(args)

                if text_content:
                    full_text = "".join(text_content).strip()
                    if full_text:
                        print(f"\n💬 Text response: {full_text}\n")


if __name__ == "__main__":
    stream_response_with_tools()

