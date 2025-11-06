#!/bin/bash
# Test if Chutes.ai backend supports <think> tags for reasoning

set -e

BACKEND="${BACKEND_URL:-https://llm.chutes.ai/v1/chat/completions}"
API_KEY="${CHUTES_API_KEY:-cpk_test}"
MODEL="${MODEL:-deepseek/deepseek-r1}"

echo "🧠 Testing Reasoning Support on Backend"
echo "=========================================="
echo "Backend: $BACKEND"
echo "Model: $MODEL"
echo

echo "Test 1: Does backend SEND reasoning_content?"
echo "---------------------------------------------"

RESPONSE=$(curl -s -N "$BACKEND" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"What is 12 * 12? Show your thinking.\"}],
    \"stream\": true,
    \"max_tokens\": 500
  }" | head -50)

if echo "$RESPONSE" | grep -q "reasoning_content"; then
    echo "✅ YES - Backend sends reasoning_content"
    echo "   Sample: $(echo "$RESPONSE" | grep reasoning_content | head -1)"
else
    echo "❌ NO - Backend does not send reasoning_content"
    echo "   The backend may not support reasoning models or uses different field"
fi

echo
echo "Test 2: Does backend ACCEPT <think> tags?"
echo "------------------------------------------"
echo "Sending message with <think> tags and checking if model understands..."

RESPONSE=$(curl -s -N "$BACKEND" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"What is 7 * 8?\"},
      {\"role\": \"assistant\", \"content\": \"<think>Let me calculate: 7 * 8 = 56</think>\\nThe answer is 56.\"},
      {\"role\": \"user\", \"content\": \"What was the calculation in your thinking?\"}
    ],
    \"stream\": true,
    \"max_tokens\": 200
  }" | grep -oP '(?<=data: )\{.*?\}' | jq -r 'select(.choices[0].delta.content != null) | .choices[0].delta.content' | head -10)

echo "Response preview:"
echo "$RESPONSE"
echo

if echo "$RESPONSE" | grep -qi "7.*8\|calculation"; then
    echo "✅ LIKELY YES - Model seems to understand <think> context"
else
    echo "⚠️  UNCLEAR - Model may treat <think> as plain text"
fi

echo
echo "Summary:"
echo "--------"
echo "Run this script to verify your backend's reasoning support."
echo "Adjust MODEL variable for different reasoning models."
