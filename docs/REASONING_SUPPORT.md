# Reasoning/Thinking Content Support

## Overview

This proxy supports reasoning content for multi-turn conversations with reasoning models (DeepSeek-R1, QwQ, etc.).

## How It Works

### Output (Backend → Client)

When the backend sends `reasoning_content` in Chat Completions:

```json
// Chat Completions Response
{
  "choices": [{
    "delta": {
      "reasoning_content": "Let me think about this..."
    }
  }]
}
```

Gets converted to Responses API events:

```json
// Responses API Events
{"type": "response.reasoning_text.delta", "delta": "Let me think..."}
{"type": "response.reasoning_text.done", "text": "Let me think about this..."}
```

✅ **This works automatically** - backend sends `reasoning_content`, we emit reasoning events.

### Input (Client → Backend)

When client sends reasoning in Responses API format:

```json
// Responses API Request
{
  "input": [
    {"type": "message", "role": "user", "content": "What is 2+2?"},
    {"type": "reasoning", "text": "I need to add 2+2..."},
    {"type": "message", "role": "assistant", "content": "The answer is 4"}
  ]
}
```

Gets converted to Chat Completions with `<think>` tags:

```json
// Chat Completions Request
{
  "messages": [
    {"role": "user", "content": "What is 2+2?"},
    {"role": "assistant", "content": "<think>I need to add 2+2...</think>\nThe answer is 4"}
  ]
}
```

❓ **This requires backend support** - the backend must understand `<think>` tags.

## Backend Requirements

### For Full Round-Trip Reasoning

The backend (Chutes.ai) must:

1. ✅ **Send reasoning in output** - via `reasoning_content` field (confirmed working)
2. ❓ **Accept reasoning in input** - via `<think>` tags in message content

**Status for Chutes.ai:**
- DeepSeek-R1, QwQ, R1-Distill → **likely support `<think>` tags** (similar to DeepSeek API)
- GPT-4o, Claude, etc. → **ignore `<think>` tags** (treat as regular text)

## Testing Reasoning Support

### Test 1: Check if backend sends reasoning

```bash
curl -N https://llm.chutes.ai/v1/chat/completions \
  -H "Authorization: Bearer cpk_your_key" \
  -d '{
    "model": "deepseek/deepseek-r1",
    "messages": [{"role": "user", "content": "What is 12 * 12?"}],
    "stream": true
  }' | grep "reasoning_content"
```

If you see `reasoning_content` → ✅ Backend sends reasoning

### Test 2: Check if backend accepts reasoning

```bash
curl -N https://llm.chutes.ai/v1/chat/completions \
  -H "Authorization: Bearer cpk_your_key" \
  -d '{
    "model": "deepseek/deepseek-r1",
    "messages": [
      {"role": "user", "content": "What is 10 * 10?"},
      {"role": "assistant", "content": "<think>10 * 10 = 100</think>\nThe answer is 100"},
      {"role": "user", "content": "What was my first question?"}
    ],
    "stream": true
  }'
```

If the model correctly recalls "10 * 10" → ✅ Backend processes `<think>` tags

## Current Implementation

### ✅ What Works

**Output conversion:**
```
Backend reasoning_content → response.reasoning_text.delta events
```

**Input conversion (3 methods):**

1. **Reasoning items:**
```json
{
  "input": [
    {"type": "reasoning", "text": "thinking..."},
    {"type": "message", "role": "assistant", "content": "answer"}
  ]
}
```
→ `<think>thinking...</think>\nanswer`

2. **Inline reasoning in content:**
```json
{
  "input": [{
    "type": "message",
    "role": "assistant",
    "content": [
      {"type": "reasoning", "text": "thinking..."},
      {"type": "input_text", "text": "answer"}
    ]
  }]
}
```
→ `<think>thinking...</think>\nanswer`

3. **From previous response:**
Use the reasoning from output in next request

### ⚠️ Backend Compatibility

**Confirmed working:**
- DeepSeek-R1 (native reasoning support)
- QwQ models (native reasoning support)
- R1-Distill models

**Partial support:**
- GPT-4o, Claude, etc. will see `<think>` as regular text

**Not tested:**
- OpenAI o1/o3 models via Chutes.ai

## Recommended Usage

### For Reasoning Models (DeepSeek-R1, QwQ)

Use reasoning items to maintain context:

```python
# First request
response1 = client.post("/v1/responses", {
  "model": "deepseek-r1",
  "input": "Solve: 15 * 23",
  "stream": True
})

# Extract reasoning from response
reasoning_text = ""  # from response.reasoning_text.delta events
answer_text = ""     # from response.output_text.delta events

# Second request with reasoning context
response2 = client.post("/v1/responses", {
  "model": "deepseek-r1",
  "input": [
    {"type": "message", "role": "user", "content": "Solve: 15 * 23"},
    {"type": "reasoning", "text": reasoning_text},
    {"type": "message", "role": "assistant", "content": answer_text},
    {"type": "message", "role": "user", "content": "Double that number"}
  ]
})
```

### For Non-Reasoning Models

Omit reasoning items - they'll be treated as text:

```python
response = client.post("/v1/responses", {
  "model": "gpt-4o",
  "input": [
    {"type": "message", "role": "user", "content": "Hello"},
    {"type": "message", "role": "assistant", "content": "Hi there!"},
    {"type": "message", "role": "user", "content": "How are you?"}
  ]
})
```

## Alternative: Encrypted Content

OpenAI Responses API mentions `reasoning.encrypted_content` for stateless mode:

```json
{
  "type": "reasoning",
  "encrypted_content": "base64_encrypted_data"
}
```

⚠️ **Not implemented** - we don't have the decryption key. This is OpenAI-specific.

## Summary

| Feature | Status | Notes |
|---------|--------|-------|
| **Output** reasoning → events | ✅ Works | Backend sends `reasoning_content` |
| **Input** reasoning items → `<think>` | ✅ Implemented | Requires backend support |
| **Input** inline reasoning → `<think>` | ✅ Implemented | Requires backend support |
| **Backend `<think>` support** | ❓ Model-dependent | Test with your model |
| **Encrypted content** | ❌ Not supported | OpenAI-specific |

## Testing

```bash
# Test reasoning output
tests/manual/reasoning_model.sh

# Test reasoning input (separate items)
tests/manual/reasoning_input.sh

# Test reasoning input (inline)
tests/manual/reasoning_inline.sh
```

## Verification Script

```bash
#!/bin/bash
# Test if your backend supports <think> tags

MODEL="deepseek/deepseek-r1"
API_KEY="cpk_your_key"

echo "Testing reasoning round-trip..."

# Send request with <think> tags
curl -s https://llm.chutes.ai/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"What is 5 * 5?\"},
      {\"role\": \"assistant\", \"content\": \"<think>5 * 5 = 25</think>\\nThe answer is 25\"},
      {\"role\": \"user\", \"content\": \"What was the calculation in your thinking?\"}
    ],
    \"stream\": true
  }" | grep -oP '(?<="content":")[^"]*' | head -5

echo
echo "If the model recalls '5 * 5', then <think> tags are processed ✅"
echo "If not, <think> tags are treated as plain text ⚠️"
```

