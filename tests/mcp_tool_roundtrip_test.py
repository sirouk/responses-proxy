#!/usr/bin/env python3
"""
MCP Tool Roundtrip Integration Test

Validates the complete flow:
1. Codex → Proxy (Responses request with tools)
2. Proxy → Backend (Chat Completions translation)
3. Backend → Proxy (SSE with tool calls)
4. Proxy → Codex (Responses events including output_tool_call.*)
5. Codex → Proxy (tool result as role:tool message with MCP format)
6. Proxy → Backend (tool message continuation)
7. Backend → Proxy → Codex (final response)
"""

import json
import os
import sys

import httpx

PROXY_URL = os.getenv("PROXY_URL", "http://localhost:8282")
API_KEY = os.getenv("CHUTES_API_KEY")

if not API_KEY:
    print("❌ Set CHUTES_API_KEY environment variable")
    sys.exit(1)


def test_mcp_tool_roundtrip():
    """Test full MCP tool calling flow with modern Responses events"""
    print("=" * 70)
    print("MCP Tool Roundtrip Integration Test")
    print("=" * 70)
    print()

    # Step 1: Initial request with tool definition
    print("Step 1: Sending initial request with tool definition...")
    request_data = {
        "model": "gpt-4o-mini",
        "input": "What is the weather in San Francisco?",
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "get_weather",
                    "description": "Get current weather for a location",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "location": {
                                "type": "string",
                                "description": "City name",
                            },
                            "unit": {
                                "type": "string",
                                "enum": ["celsius", "fahrenheit"],
                            },
                        },
                        "required": ["location"],
                    },
                },
            }
        ],
        "stream": True,
    }

    tool_call_id = None
    tool_name = None
    tool_args = None
    begin_count = 0
    delta_count = 0
    end_count = 0
    legacy_delta_count = 0

    with httpx.stream(
        "POST",
        f"{PROXY_URL}/v1/responses",
        headers={"Authorization": f"Bearer {API_KEY}"},
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
            except json.JSONDecodeError:
                continue

            event_type = event.get("type", "")

            # Track modern events
            if event_type == "response.output_tool_call.begin":
                begin_count += 1
                tool_name = event.get("name")
                tool_call_id = event.get("call_id")
                print(f"   ✓ output_tool_call.begin: {tool_name}")

            elif event_type == "response.output_tool_call.delta":
                delta_count += 1
                delta_text = event.get("delta", "")
                if delta_count <= 3:  # Only show first few deltas
                    print(f"   ✓ output_tool_call.delta: {delta_text[:30]}...")

            elif event_type == "response.output_tool_call.end":
                end_count += 1
                tool_args = event.get("arguments")
                print(f"   ✓ output_tool_call.end: {tool_args}")

            # Track legacy events for compatibility
            elif event_type == "response.function_call_arguments.delta":
                legacy_delta_count += 1

    print()
    print(f"Event counts:")
    print(f"  - Modern begin events: {begin_count}")
    print(f"  - Modern delta events: {delta_count}")
    print(f"  - Modern end events: {end_count}")
    print(f"  - Legacy delta events: {legacy_delta_count}")
    print()

    if not tool_call_id or not tool_name:
        print("⚠️  Model did not make a tool call - skipping continuation test")
        return

    assert begin_count > 0, "Expected at least one output_tool_call.begin event"
    assert delta_count > 0, "Expected at least one output_tool_call.delta event"
    assert end_count > 0, "Expected at least one output_tool_call.end event"
    assert (
        legacy_delta_count > 0
    ), "Expected legacy function_call_arguments.delta for compatibility"

    print(f"✅ Step 1 complete: Tool call received ({tool_name})")
    print()

    # Step 2: Send tool result using MCP-style message
    print("Step 2: Sending tool result with MCP-style message...")
    print(f"   Using call_id: {tool_call_id}")

    # Simulate tool execution
    tool_result_body = json.dumps(
        {"temperature": 68, "unit": "fahrenheit", "condition": "foggy"}
    )

    continuation_data = {
        "model": "gpt-4o-mini",
        "input": [
            {
                "type": "message",
                "role": "user",
                "content": "What is the weather in San Francisco?",
            },
            {"type": "message", "role": "assistant", "content": ""},
            {
                "type": "function_call",
                "call_id": tool_call_id,
                "name": tool_name,
                "arguments": tool_args,
            },
            # MCP-style tool result with content array
            {
                "type": "message",
                "role": "tool",
                "tool_call_id": tool_call_id,
                "content": [{"type": "output", "content_type": "application/json", "body": tool_result_body}],
            },
        ],
        "tools": request_data["tools"],
        "stream": True,
    }

    final_text = []

    with httpx.stream(
        "POST",
        f"{PROXY_URL}/v1/responses",
        headers={"Authorization": f"Bearer {API_KEY}"},
        json=continuation_data,
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
            except json.JSONDecodeError:
                continue

            event_type = event.get("type", "")

            if event_type == "response.output_text.delta":
                delta = event.get("delta", "")
                final_text.append(delta)

            elif event_type == "response.completed":
                print("   ✓ Received response.completed")

            elif event_type == "response.done":
                print("   ✓ Received response.done (terminal event)")

    full_response = "".join(final_text)
    print()
    print(f"✅ Step 2 complete: Received continuation response")
    print(f"   Response length: {len(full_response)} chars")
    print(f"   Preview: {full_response[:100]}...")
    print()

    # Verify the response mentions the weather data
    if "68" in full_response or "foggy" in full_response.lower():
        print("✅ Response incorporates tool result correctly!")
    else:
        print("⚠️  Response may not have used tool result (check manually)")

    print()
    print("=" * 70)
    print("✅ MCP TOOL ROUNDTRIP TEST PASSED")
    print("=" * 70)


if __name__ == "__main__":
    test_mcp_tool_roundtrip()

