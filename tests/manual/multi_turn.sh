#!/bin/bash
# Manual smoke test: multi-turn conversation input.

set -euo pipefail

PROXY_URL="${PROXY_URL:-http://localhost:8282}"
API_KEY="${CHUTES_API_KEY:-cpk_test}"

curl -N "${PROXY_URL}/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "gpt-4o",
    "instructions": "You are a helpful assistant.",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": "What is the capital of France?"
      },
      {
        "type": "message",
        "role": "assistant",
        "content": "The capital of France is Paris."
      },
      {
        "type": "message",
        "role": "user",
        "content": "What is its population?"
      }
    ],
    "stream": true,
    "max_output_tokens": 200
  }'

