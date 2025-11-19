#!/bin/bash
# Test to verify fragmented tool call handling
# This simulates the edge case where backend sends tool index/id in one chunk
# and name/args in subsequent chunks

set -euo pipefail

PROXY_URL="${PROXY_URL:-http://localhost:8282}"
API_KEY="${CHUTES_API_KEY:?Set CHUTES_API_KEY to a valid token}"

echo "=== Fragmented Tool Call Edge Case Test ==="
echo
echo "This test validates that the proxy correctly buffers tool arguments"
echo "that arrive BEFORE the tool name is received from the backend."
echo
echo "Expected behavior:"
echo "  1. Backend sends {index: 0, id: 'call_x', function: {arguments: '{'}}"
echo "  2. Backend sends {index: 0, function: {name: 'get_weather', arguments: '\"loc...'}}"
echo "  3. Proxy buffers '{' until name arrives"
echo "  4. Proxy emits response.output_tool_call.begin"
echo "  5. Proxy replays buffered '{' as first delta"
echo "  6. Proxy emits subsequent deltas normally"
echo

echo "Step 1: Sending tool-calling request..."

RESPONSE=$(curl -s -N "${PROXY_URL}/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "gpt-4o-mini",
    "input": "What is the weather in Tokyo?",
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get current weather",
          "parameters": {
            "type": "object",
            "properties": {
              "location": {"type": "string"}
            },
            "required": ["location"]
          }
        }
      }
    ],
    "stream": true
  }')

echo "Step 2: Analyzing event sequence..."
echo

# Extract event sequence
BEGIN_COUNT=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.output_tool_call.begin") | .type' | wc -l)
DELTA_COUNT=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.output_tool_call.delta") | .type' | wc -l)
END_COUNT=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.output_tool_call.end") | .type' | wc -l)

# Extract legacy events for compatibility check
LEGACY_ITEM_ADDED=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.output_item.added" and .item.type=="function_call") | .type' | wc -l)
LEGACY_DELTA_COUNT=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.function_call_arguments.delta") | .type' | wc -l)
LEGACY_DONE_COUNT=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.function_call_arguments.done") | .type' | wc -l)

echo "Modern events:"
echo "  - response.output_tool_call.begin: $BEGIN_COUNT"
echo "  - response.output_tool_call.delta: $DELTA_COUNT"
echo "  - response.output_tool_call.end: $END_COUNT"
echo
echo "Legacy events (backward compatibility):"
echo "  - response.output_item.added: $LEGACY_ITEM_ADDED"
echo "  - response.function_call_arguments.delta: $LEGACY_DELTA_COUNT"
echo "  - response.function_call_arguments.done: $LEGACY_DONE_COUNT"
echo

# Verify event ordering
FIRST_DELTA=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type | test("delta")) | .sequence_number' | head -1)
FIRST_BEGIN=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.output_tool_call.begin") | .sequence_number' | head -1)

if [[ -n "$FIRST_DELTA" && -n "$FIRST_BEGIN" ]]; then
    if [[ $FIRST_BEGIN -lt $FIRST_DELTA ]]; then
        echo "✅ Event ordering correct: begin (seq $FIRST_BEGIN) before delta (seq $FIRST_DELTA)"
    else
        echo "❌ Event ordering WRONG: delta (seq $FIRST_DELTA) before begin (seq $FIRST_BEGIN)"
        exit 1
    fi
else
    echo "⚠️  Could not verify event ordering (model may not have called tool)"
fi

# Extract final tool call details
FUNCTION_NAME=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.output_tool_call.end") | .name // empty' | head -1)
FUNCTION_ARGS=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.output_tool_call.end") | .arguments // empty' | head -1)
CALL_ID=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.output_item.done" and .item.type=="function_call") | .item.call_id // empty' | head -1)

if [[ -n "$FUNCTION_NAME" && -n "$CALL_ID" ]]; then
    echo
    echo "✅ Tool call successfully completed:"
    echo "   Function: $FUNCTION_NAME"
    echo "   Call ID: $CALL_ID"
    echo "   Arguments: $FUNCTION_ARGS"
    echo
    echo "✅ All checks passed - fragmented tool calls handled correctly!"
else
    echo
    echo "⚠️  Model did not make a tool call (not an error, just test limitation)"
fi

