#!/bin/bash
# Manual smoke test: reasoning item provided as separate input entry.

set -euo pipefail

PROXY_URL="${PROXY_URL:-http://localhost:8282}"
API_KEY="${CHUTES_API_KEY:-cpk_test}"

curl -N "${PROXY_URL}/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "deepseek/deepseek-r1",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": "What is 12 * 12?"
      },
      {
        "type": "reasoning",
        "text": "I need to calculate 12 * 12. Let me break this down: 12 * 12 = 12 * 10 + 12 * 2 = 120 + 24 = 144"
      },
      {
        "type": "message",
        "role": "assistant",
        "content": "12 * 12 equals 144"
      },
      {
        "type": "message",
        "role": "user",
        "content": "Now what is the square root of that number?"
      }
    ],
    "stream": true,
    "max_output_tokens": 2000
  }'

echo
echo "Note: Reasoning item should be converted to <think> content in the proxy."

