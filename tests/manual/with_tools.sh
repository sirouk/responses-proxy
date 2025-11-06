#!/bin/bash
# Manual smoke test: function tool definition with streaming output.

set -euo pipefail

PROXY_URL="${PROXY_URL:-http://localhost:8282}"
API_KEY="${CHUTES_API_KEY:-cpk_test}"

curl -N "${PROXY_URL}/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "gpt-4o",
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
                "description": "City name"
              }
            },
            "required": ["location"]
          }
        }
      }
    ],
    "stream": true,
    "max_output_tokens": 200
  }'

