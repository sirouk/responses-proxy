#!/bin/bash
# Manual smoke test: reasoning model stream (looks for reasoning events).

set -euo pipefail

PROXY_URL="${PROXY_URL:-http://localhost:8282}"
API_KEY="${CHUTES_API_KEY:-cpk_test}"

curl -N "${PROXY_URL}/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "deepseek/deepseek-r1",
    "input": "What is the square root of 144? Show your reasoning.",
    "stream": true,
    "max_output_tokens": 2000
  }' |
  grep -E '"type":"response\.(reasoning_text|output_text)\.(delta|done)"' --line-buffered | head -20

echo
echo "Note: Look for response.reasoning_text.delta events for thinking content."

