#!/bin/bash

# Test script for tool calling functionality (manual).

PROXY_URL="${PROXY_URL:-http://localhost:8282}"
API_KEY="${CHUTES_API_KEY:?Set CHUTES_API_KEY to run this test}"

if [ -z "$API_KEY" ]; then
    echo "Error: OPENAI_API_KEY environment variable not set"
    exit 1
fi

echo "Testing tool calling with Responses API proxy..."
echo "Proxy: $PROXY_URL"
echo ""

# Test 1: Simple function calling
echo "=== Test 1: Function calling with get_weather ==="
curl -s "${PROXY_URL}/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "input": "What is the weather like in San Francisco?",
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
                "description": "The city and state, e.g. San Francisco, CA"
              },
              "unit": {
                "type": "string",
                "enum": ["celsius", "fahrenheit"]
              }
            },
            "required": ["location"]
          }
        }
      }
    ],
    "tool_choice": "auto",
    "stream": true
  }' | while IFS= read -r line; do
    if [[ $line == data:* ]]; then
        event_data="${line#data: }"
        if [[ $event_data != "[DONE]" ]] && [[ -n "$event_data" ]]; then
            echo "$event_data" | jq -c '{type, item_id, name, arguments: (.arguments // .delta)}'
        fi
    fi
done

echo ""
echo ""

# Test 2: Parallel tool calls
echo "=== Test 2: Parallel function calling ==="
curl -s "${PROXY_URL}/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "input": "What is the weather in San Francisco and New York?",
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
                "type": "string"
              }
            },
            "required": ["location"]
          }
        }
      }
    ],
    "parallel_tool_calls": true,
    "stream": true
  }' | while IFS= read -r line; do
    if [[ $line == data:* ]]; then
        event_data="${line#data: }"
        if [[ $event_data != "[DONE]" ]] && [[ -n "$event_data" ]]; then
            echo "$event_data" | jq -c '{type, output_index, name, call_id}'
        fi
    fi
done

echo ""
echo ""

# Test 3: Force specific tool
echo "=== Test 3: Forced tool choice ==="
curl -s "${PROXY_URL}/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "input": "Tell me about the weather",
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get weather",
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
    "tool_choice": {
      "type": "function",
      "function": {"name": "get_weather"}
    },
    "stream": true
  }' | while IFS= read -r line; do
    if [[ $line == data:* ]]; then
        event_data="${line#data: }"
        if [[ $event_data != "[DONE]" ]] && [[ -n "$event_data" ]]; then
            event_type=$(echo "$event_data" | jq -r '.type')
            if [[ $event_type == *"function_call"* ]] || [[ $event_type == "response.completed" ]]; then
                echo "$event_data" | jq -c '.'
            fi
        fi
    fi
done

echo ""
echo "Tests complete!"




