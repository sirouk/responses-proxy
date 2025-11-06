#!/bin/bash
# Manual smoke test: reasoning inside assistant content parts.

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
        "content": "Solve: 15 + 27"
      },
      {
        "type": "message",
        "role": "assistant",
        "content": [
          {
            "type": "reasoning",
            "text": "To solve 15 + 27: Start with 15, add 20 to get 35, then add 7 more to get 42"
          },
          {
            "type": "input_text",
            "text": "The sum is 42"
          }
        ]
      },
      {
        "type": "message",
        "role": "user",
        "content": "What is double that number?"
      }
    ],
    "stream": true,
    "max_output_tokens": 1000
  }'

echo
echo "Note: Inline reasoning should appear as <think> tags in the proxied output."

