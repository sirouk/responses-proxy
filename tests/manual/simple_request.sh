#!/bin/bash
# Manual smoke test: simple streaming request.
#
# Environment:
#   PROXY_URL       (default: http://localhost:8282)
#   CHUTES_API_KEY  (default: cpk_test)

set -euo pipefail

PROXY_URL="${PROXY_URL:-http://localhost:8282}"
API_KEY="${CHUTES_API_KEY:-cpk_test}"

curl -N "${PROXY_URL}/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "gpt-4o",
    "input": "Tell me a short joke",
    "stream": true,
    "max_output_tokens": 100
  }'

