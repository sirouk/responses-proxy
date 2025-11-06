#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PROXY_URL="${PROXY_URL:-http://localhost:8282}"
API_KEY="${CHUTES_API_KEY:-cpk_test}"

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  OpenAI Responses Proxy - Test Suite    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo

# Test 1: Health Check
echo -e "${YELLOW}Test 1: Health Check${NC}"
echo "---"
curl -s "$PROXY_URL/health" | jq .
echo
echo

# Test 2: Simple Text Request (Streaming)
echo -e "${YELLOW}Test 2: Simple Text Request (Streaming)${NC}"
echo "---"
curl -N -s "$PROXY_URL/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "gpt-4o",
    "input": "Say hello in exactly 5 words",
    "stream": true,
    "max_output_tokens": 20
  }'
echo
echo

# Test 3: Structured Input
echo -e "${YELLOW}Test 3: Structured Input with Instructions${NC}"
echo "---"
curl -N -s "$PROXY_URL/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "gpt-4o",
    "instructions": "You are a helpful math tutor.",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": "What is 2+2?"
      }
    ],
    "stream": true,
    "max_output_tokens": 50
  }'
echo
echo

# Test 4: Multi-turn Conversation
echo -e "${YELLOW}Test 4: Multi-turn Conversation${NC}"
echo "---"
curl -N -s "$PROXY_URL/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "gpt-4o",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": "My name is Alice"
      },
      {
        "type": "message",
        "role": "assistant",
        "content": "Hello Alice! Nice to meet you."
      },
      {
        "type": "message",
        "role": "user",
        "content": "What is my name?"
      }
    ],
    "stream": true,
    "max_output_tokens": 30
  }'
echo
echo

echo -e "${GREEN}✓ All tests completed${NC}"

