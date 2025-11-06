# OpenAI Responses API vs Chat Completions

## Overview

This proxy bridges the gap between OpenAI's newer Responses API and the traditional Chat Completions API used by Chutes.ai.

## API Differences

### Request Format

**Responses API (OpenAI):**
```json
{
  "model": "gpt-4o",
  "input": "What is AI?",
  "instructions": "Be concise",
  "max_output_tokens": 1024,
  "stream": true
}
```

**Chat Completions API (Chutes.ai):**
```json
{
  "model": "gpt-4o",
  "messages": [
    {"role": "system", "content": "Be concise"},
    {"role": "user", "content": "What is AI?"}
  ],
  "max_tokens": 1024,
  "stream": true
}
```

### Response Format

**Responses API Events:**
- `response.created`
- `response.output_item.added`
- `response.content_part.added`
- `response.output_text.delta`
- `response.output_text.done`
- `response.content_part.done`
- `response.output_item.done`
- `response.completed`

**Chat Completions Events:**
- Single SSE stream
- `choices[0].delta.content` for text
- `choices[0].finish_reason` for completion

## Feature Mapping

| Feature | Responses API | Chat Completions | Supported |
|---------|---------------|------------------|-----------|
| Text input/output | ✅ | ✅ | ✅ |
| Multi-turn conversations | ✅ | ✅ | ✅ |
| System instructions | `instructions` | `messages[0].role=system` | ✅ |
| Function calling | `tools` | `tools` | ✅ |
| Image inputs | ✅ | ✅ | ✅ |
| Streaming | ✅ | ✅ | ✅ |
| Temperature control | ✅ | ✅ | ✅ |
| Max tokens | `max_output_tokens` | `max_tokens` | ✅ |
| Conversation state | `conversation` object | N/A | ❌ (stateless) |
| Previous response | `previous_response_id` | N/A | ❌ (stateless) |
| Item references | `item_reference` | N/A | ❌ (logged, ignored) |
| Response storage | `store` parameter | N/A | ❌ (not implemented) |
| Audio output | ✅ (OpenAI) | ❌ | ❌ (backend limitation) |
| Image output | ✅ (OpenAI) | ❌ | ❌ (backend limitation) |

## Conversion Examples

### Example 1: Simple Request

**Responses API Input:**
```json
{
  "model": "gpt-4o",
  "input": "Tell me a joke"
}
```

**Converted to Chat Completions:**
```json
{
  "model": "gpt-4o",
  "messages": [
    {"role": "user", "content": "Tell me a joke"}
  ],
  "stream": true
}
```

### Example 2: With Instructions

**Responses API Input:**
```json
{
  "model": "gpt-4o",
  "instructions": "You are a helpful assistant",
  "input": "What is AI?"
}
```

**Converted to Chat Completions:**
```json
{
  "model": "gpt-4o",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant"},
    {"role": "user", "content": "What is AI?"}
  ],
  "stream": true
}
```

### Example 3: Multi-turn

**Responses API Input:**
```json
{
  "model": "gpt-4o",
  "input": [
    {
      "type": "message",
      "role": "user",
      "content": "Hi"
    },
    {
      "type": "message",
      "role": "assistant",
      "content": "Hello!"
    },
    {
      "type": "message",
      "role": "user",
      "content": "How are you?"
    }
  ]
}
```

**Converted to Chat Completions:**
```json
{
  "model": "gpt-4o",
  "messages": [
    {"role": "user", "content": "Hi"},
    {"role": "assistant", "content": "Hello!"},
    {"role": "user", "content": "How are you?"}
  ],
  "stream": true
}
```

## Status Mapping

| Chat Completions | Responses API |
|------------------|---------------|
| `finish_reason: "stop"` | `status: "completed"` |
| `finish_reason: "length"` | `status: "incomplete"` |
| `finish_reason: "content_filter"` | `status: "failed"` |
| `finish_reason: "tool_calls"` | `status: "completed"` |
| Error response | `status: "failed"` |

## Limitations

### Current Limitations

1. **No Conversation State**
   - Cannot use `previous_response_id`
   - Cannot use `item_reference`
   - Client must manage full conversation history

2. **No Response Storage**
   - `store` parameter ignored
   - Cannot retrieve past responses
   - No GET /v1/responses/{id}

3. **Limited Tool Support**
   - Basic function calling works
   - Complex tool results need testing
   - No built-in tools (file_search, code_interpreter)

4. **Text Only**
   - No audio input/output
   - No image generation
   - Images as input only

### Backend Limitations

These are limitations of the Chat Completions API:

- No native reasoning/thinking content
- No structured output items array
- Different event format

## Benefits of This Approach

1. **Compatibility** - Use OpenAI SDKs with Chutes.ai backend
2. **Simplicity** - Stateless design, easy to scale
3. **Performance** - Low overhead, efficient streaming
4. **Reliability** - No state to corrupt, simple recovery
5. **Maintainability** - Clean Rust code, well-tested

## When to Use

**Use this proxy when:**
- You want OpenAI Responses API compatibility with Chutes.ai
- You're migrating from OpenAI to Chutes.ai
- You want to use OpenAI SDK libraries
- You need stateless request/response

**Don't use this proxy when:**
- You need conversation state management
- You need response storage and retrieval
- You need built-in tools (file_search, etc.)
- You can use Chat Completions API directly

## Migration Guide

### From OpenAI Responses API

**Fully Compatible:**
- Simple text requests
- Multi-turn conversations (pass full history)
- Function calling
- Image inputs
- Streaming

**Requires Changes:**
- Remove `previous_response_id` (pass full conversation in `input`)
- Remove `item_reference` (expand references to full messages)
- Remove `store: true` (not implemented)
- Remove `conversation` object (stateless)

### From Chat Completions

**Already Compatible!**

No changes needed - the proxy accepts Responses API format and converts it.

**Optional Migration:**
- Use `input` instead of `messages`
- Use `instructions` instead of system message
- Use `max_output_tokens` instead of `max_tokens`

## Authorization Header Forwarding - Comparison

## TL;DR
✅ **Both proxies forward auth correctly** using `.bearer_auth(key)`  
⚠️ **Minor difference**: Responses proxy missing Anthropic token check

---

## Claude Proxy Implementation

```rust
// Auth: Forward client key to backend, or reject if invalid/missing
if let Some(key) = &client_key {
    if key.contains("sk-ant-") {
        log::warn!("❌ Anthropic OAuth tokens (sk-ant-*) are not supported - use backend-compatible key (cpk_*)");
        return Err((StatusCode::UNAUTHORIZED, "invalid_auth_token"));
    }
    req = req.bearer_auth(key);
    log::info!("🔄 Auth: Forwarding client key to backend");
} else {
    log::warn!("❌ No client API key provided");
    return Err((StatusCode::UNAUTHORIZED, "missing_api_key"));
}
```

**Flow:**
1. Extract key
2. Check for invalid Anthropic OAuth tokens (`sk-ant-*`)
3. Forward key to backend OR reject

---

## Responses Proxy Implementation

```rust
// Extract and validate auth
let client_key = extract_client_key(&headers);

if let Some(key) = &client_key {
    log::info!("🔑 Client API Key: Bearer {}", mask_token(key));
} else {
    log::warn!("❌ No client API key provided");
    return Err((StatusCode::UNAUTHORIZED, "missing_api_key"));
}

// ... (conversion logic) ...

// Forward client auth to backend
if let Some(key) = &client_key {
    backend_req = backend_req.bearer_auth(key);
    log::info!("🔄 Auth: Forwarding client key to backend");
}
```

**Flow:**
1. Extract key
2. Validate key exists (reject if missing)
3. ... do conversion ...
4. Forward key to backend

---

## Key Differences

### 1. Anthropic Token Check ⚠️
**Claude proxy**: Explicitly rejects `sk-ant-*` tokens  
**Responses proxy**: **Missing this check**

**Why it matters:**
- Anthropic OAuth tokens (`sk-ant-sid_*`) won't work with Chutes backend
- Better to reject early with clear message vs backend 401
- Improves user experience

### 2. Code Structure
**Claude proxy**: Single combined check  
**Responses proxy**: Split validation (early check + later forward)

**Impact:** Responses proxy has redundant `if let Some(key)` at line 121 since we already validated at line 88

---

## Recommendation

Add Anthropic token check to responses proxy for consistency:

```rust
// Extract and validate auth
let client_key = extract_client_key(&headers);

if let Some(key) = &client_key {
    // Reject Anthropic OAuth tokens (not compatible with backend)
    if key.contains("sk-ant-") {
        log::warn!("❌ Anthropic OAuth tokens (sk-ant-*) are not supported - use backend-compatible key (cpk_*)");
        return Err((StatusCode::UNAUTHORIZED, "invalid_auth_token"));
    }
    log::info!("🔑 Client API Key: Bearer {}", mask_token(key));
} else {
    log::warn!("❌ No client API key provided");
    return Err((StatusCode::UNAUTHORIZED, "missing_api_key"));
}
```

**Benefits:**
- ✅ Consistent with claude-proxy
- ✅ Better error messages for users
- ✅ Fails fast (before conversion/backend call)

**Optional cleanup:**
Since we validate key exists early, the later check is guaranteed to succeed:
```rust
// This is now guaranteed to have a key
backend_req = backend_req.bearer_auth(client_key.as_ref().unwrap());
log::info!("🔄 Auth: Forwarding client key to backend");
```

---

## Current Status

| Aspect | Claude Proxy | Responses Proxy | Status |
|--------|--------------|-----------------|--------|
| **Extracts key** | ✅ | ✅ | Equal |
| **Validates exists** | ✅ | ✅ | Equal |
| **Rejects Anthropic tokens** | ✅ | ❌ | **Missing** |
| **Forwards to backend** | ✅ | ✅ | Equal |
| **Uses `.bearer_auth()`** | ✅ | ✅ | Equal |

---

## Conclusion

✅ **Core functionality identical**: Both forward Authorization correctly  
⚠️ **Minor gap**: Add Anthropic token check for better UX  
⚪ **Optional**: Simplify redundant check

**Priority**: LOW (works fine, just inconsistent user experience)

