#!/usr/bin/env python3
"""
Example Python client for OpenAI Responses API Proxy.

This script is intended for manual smoke-testing. It requires a live proxy
endpoint and valid API key; it is not wired into automated CI.
"""

import json
import os
from typing import Iterable

import requests

PROXY_URL = os.getenv("PROXY_URL", "http://localhost:8282")
API_KEY = os.getenv("CHUTES_API_KEY", "cpk_test")


def _stream_lines(response: requests.Response) -> Iterable[dict]:
    """Yield parsed SSE events from a requests streaming response."""
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
    """Issue a basic streaming prompt and print deltas."""
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

    for event in _stream_lines(response):
        event_type = event.get("type")
        if event_type == "response.output_text.delta":
            print(f"Δ {event.get('delta', '')}")
        elif event_type == "response.completed":
            status = event.get("response", {}).get("status")
            print(f"\nStatus: {status}")

    print()


def multi_turn_conversation() -> None:
    """Demonstrate structured multi-turn input."""
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

    transcript = []
    for event in _stream_lines(response):
        if event.get("type") == "response.output_text.delta":
            delta = event.get("delta", "")
            transcript.append(delta)
            print(delta, end="", flush=True)

    print("\n\nFull response:")
    print("".join(transcript))
    print()


if __name__ == "__main__":
    simple_request()
    multi_turn_conversation()
