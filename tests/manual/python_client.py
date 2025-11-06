#!/usr/bin/env python3
"""
Manual smoke-test client for the OpenAI Responses Proxy.

Requires:
- PROXY_URL (default: http://localhost:8282)
- CHUTES_API_KEY (default: cpk_test)

Usage:
    python tests/manual/python_client.py

This script streams events and dumps output to stdout. It is not wired into CI.
"""

from __future__ import annotations

import json
import os
from typing import Dict, Iterable

import requests

PROXY_URL = os.getenv("PROXY_URL", "http://localhost:8282")
API_KEY = os.getenv("CHUTES_API_KEY", "cpk_test")


def _stream_events(response: requests.Response) -> Iterable[Dict[str, object]]:
    """Yield parsed SSE events from a streaming `requests` response."""

    for raw_line in response.iter_lines():
        if not raw_line:
            continue

        line = raw_line.decode("utf-8")
        if not line.startswith("data: "):
            continue

        payload = line[6:]
        if payload == "[DONE]":
            break

        try:
            yield json.loads(payload)
        except json.JSONDecodeError:
            yield {"type": "raw", "payload": payload}


def simple_request() -> None:
    print("=== Simple Request ===\n")

    response = requests.post(
        f"{PROXY_URL}/v1/responses",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {API_KEY}",
        },
        json={
            "model": "gpt-4o",
            "input": "Tell me a short joke",
            "stream": True,
            "max_output_tokens": 100,
        },
        stream=True,
        timeout=60,
    )
    response.raise_for_status()

    for event in _stream_events(response):
        event_type = event.get("type")
        if event_type == "response.output_text.delta":
            print(f"Δ {event.get('delta', '')}")
        elif event_type == "response.completed":
            status = event.get("response", {}).get("status")
            print(f"\nStatus: {status}\n")


def multi_turn_conversation() -> None:
    print("=== Multi-turn Conversation ===\n")

    response = requests.post(
        f"{PROXY_URL}/v1/responses",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {API_KEY}",
        },
        json={
            "model": "gpt-4o",
            "instructions": "You are a helpful assistant.",
            "input": [
                {
                    "type": "message",
                    "role": "user",
                    "content": "What is the capital of France?",
                },
                {
                    "type": "message",
                    "role": "assistant",
                    "content": "The capital of France is Paris.",
                },
                {
                    "type": "message",
                    "role": "user",
                    "content": "What is its population?",
                },
            ],
            "stream": True,
            "max_output_tokens": 200,
        },
        stream=True,
        timeout=60,
    )
    response.raise_for_status()

    transcript: list[str] = []
    for event in _stream_events(response):
        if event.get("type") == "response.output_text.delta":
            delta = event.get("delta", "")
            transcript.append(delta)
            print(delta, end="", flush=True)

    print("\n\nFull response:\n" + "".join(transcript) + "\n")


if __name__ == "__main__":
    simple_request()
    multi_turn_conversation()

