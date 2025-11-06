#!/bin/bash
# Manual walkthrough: tool call, simulate execution, send result back.

set -euo pipefail

PROXY_URL="${PROXY_URL:-http://localhost:8282}"
API_KEY="${CHUTES_API_KEY:?Set CHUTES_API_KEY to a valid token}"

echo "=== Tool Calling Example with Multi-Turn Conversation ==="
echo

echo "Step 1: Ask about the weather and capture the tool call..."

RESPONSE=$(curl -s -N "${PROXY_URL}/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "gpt-4o-mini",
    "input": "What is the weather like in San Francisco? I want to know the temperature.",
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get the current weather in a given location",
          "parameters": {
            "type": "object",
            "properties": {
              "location": {
                "type": "string",
                "description": "City and state (e.g. San Francisco, CA)"
              },
              "unit": {
                "type": "string",
                "enum": ["celsius", "fahrenheit"],
                "description": "Temperature unit"
              }
            },
            "required": ["location"]
          }
        }
      }
    ],
    "tool_choice": "auto",
    "stream": true
  }')

FUNCTION_NAME=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.function_call_arguments.done") | .name' | head -1)
FUNCTION_ARGS=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.function_call_arguments.done") | .arguments' | head -1)
CALL_ID=$(echo "$RESPONSE" | grep '^data:' | sed 's/^data: //' | jq -r 'select(.type=="response.output_item.done") | .item.call_id' | head -1)

if [[ -z "$FUNCTION_NAME" || -z "$CALL_ID" ]]; then
  echo "❌ Expected a function call but none was emitted" >&2
  exit 1
fi

echo "Function: $FUNCTION_NAME"
echo "Arguments: $FUNCTION_ARGS"
echo "Call ID: $CALL_ID"
echo

echo "Step 2: Simulate executing the function..."
FUNCTION_RESULT='{"temperature":72,"unit":"fahrenheit","condition":"sunny","humidity":65}'
echo "Result: $FUNCTION_RESULT"
echo

echo "Step 3: Send the function result back and stream the reply..."

curl -s -N "${PROXY_URL}/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d "$(jq -n --arg call_id "$CALL_ID" --arg name "$FUNCTION_NAME" --argjson args "$FUNCTION_ARGS" --arg result "$FUNCTION_RESULT" '{
    model: "gpt-4o-mini",
    input: [
      {type: "message", role: "user", content: "What is the weather like in San Francisco? I want to know the temperature."},
      {type: "message", role: "assistant", content: ""},
      {type: "function_call", call_id: $call_id, name: $name, arguments: ($args // "{}")},
      {type: "function_call_output", call_id: $call_id, output: $result}
    ],
    tools: [
      {
        type: "function",
        function: {
          name: "get_weather",
          description: "Get the current weather in a given location",
          parameters: {
            type: "object",
            properties: {
              location: {type: "string"},
              unit: {type: "string", enum: ["celsius", "fahrenheit"]}
            },
            required: ["location"]
          }
        }
      }
    ],
    stream: true
  }')" |
  while IFS= read -r line; do
    [[ $line == data:* ]] || continue
    payload="${line#data: }"
    [[ $payload == "[DONE]" ]] && break
    event_type=$(echo "$payload" | jq -r '.type')
    if [[ $event_type == "response.output_text.delta" ]]; then
      echo "$payload" | jq -r '.delta'
    elif [[ $event_type == "response.completed" ]]; then
      echo
      echo "✅ Conversation complete!"
    fi
  done

