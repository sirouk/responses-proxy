# Tool Calling Implementation

Full implementation of OpenAI Responses API tool calling (function calling) with proper event streaming.

## Features

- ✅ **Function definitions** - Define tools with JSON schema parameters
- ✅ **Tool choice control** - `auto`, `none`, `required`, or force specific tool
- ✅ **Parallel tool calls** - Multiple simultaneous function calls
- ✅ **Streaming events** - Proper delta and done events for function arguments
- ✅ **Multi-turn support** - Send function results back for continued conversation
- ✅ **Type safety** - Full Rust type system for tool call states
- ✅ **Resilient parsing** - Converts stray XML-style tool call text into real function calls

## Supported Parameters

### Request Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `tools` | array | Array of tool definitions (currently supports `type: "function"`) |
| `tool_choice` | string or object | How model selects tools |
| `parallel_tool_calls` | boolean | Enable parallel function execution (default: true) |

### Tool Choice Values

```json
// Let model decide (default)
"tool_choice": "auto"

// Disable all tools
"tool_choice": "none"

// Require at least one tool call
"tool_choice": "required"

// Force specific tool
"tool_choice": {
  "type": "function",
  "function": {"name": "get_weather"}
}
```

## Tool Definition Format

```json
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
          "description": "City and state"
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
```

## XML-Style Compatibility Layer

Some upstream providers still emit ad-hoc XML wrappers for tool calls (for example `<function=apply_patch>` blocks). The proxy detects these fragments in assistant deltas, strips them from the visible text, and emits proper `function_call` items with JSON arguments. This conversion is guarded so that:

- Plain text responses remain untouched when no XML markers are present.
- Multiple tool calls in a single block are converted sequentially with deterministic IDs.
- The cleaned assistant text continues streaming to the client without exposing the raw XML.

This behaviour is automatic—no additional configuration required.

## Event Sequence

When the model calls a function, you'll receive these events:

### 1. Output Item Added
```json
{
  "type": "response.output_item.added",
  "item_id": "call_abc123",
  "output_index": 1,
  "item": {
    "id": "call_abc123",
    "type": "function_call",
    "status": "in_progress",
    "call_id": "call_xyz",
    "name": "get_weather",
    "arguments": ""
  }
}
```

### 2. Arguments Delta (streaming)
```json
{
  "type": "response.function_call_arguments.delta",
  "item_id": "call_abc123",
  "output_index": 1,
  "delta": "{\"location\":"
}
```

### 3. Arguments Done
```json
{
  "type": "response.function_call_arguments.done",
  "item_id": "call_abc123",
  "output_index": 1,
  "name": "get_weather",
  "arguments": "{\"location\":\"San Francisco, CA\"}"
}
```

### 4. Output Item Done
```json
{
  "type": "response.output_item.done",
  "item_id": "call_abc123",
  "output_index": 1,
  "item": {
    "id": "call_abc123",
    "type": "function_call",
    "status": "completed",
    "call_id": "call_xyz",
    "name": "get_weather",
    "arguments": "{\"location\":\"San Francisco, CA\"}"
  }
}
```

### 5. Response Completed
```json
{
  "type": "response.completed",
  "response": {
    "id": "resp_123",
    "status": "completed",
    "output": [
      {
        "type": "message",
        "role": "assistant",
        "content": [...]
      },
      {
        "type": "function_call",
        "call_id": "call_xyz",
        "name": "get_weather",
        "arguments": "{\"location\":\"San Francisco, CA\"}"
      }
    ]
  }
}
```

## Multi-Turn Conversations

To continue a conversation after a tool call:

1. **Extract function call from response** - Get `call_id`, `name`, and `arguments`
2. **Execute the function** - Run your actual function code
3. **Send result back** - Include previous messages plus function result

```json
{
  "model": "gpt-4o-mini",
  "input": [
    {"type": "message", "role": "user", "content": "What's the weather?"},
    {"type": "message", "role": "assistant", "content": ""},
    {
      "type": "function_call",
      "call_id": "call_xyz",
      "name": "get_weather",
      "arguments": "{\"location\":\"San Francisco\"}"
    },
    {
      "type": "function_call_output",
      "call_id": "call_xyz",
      "output": "{\"temp\":72,\"condition\":\"sunny\"}"
    }
  ],
  "tools": [...],
  "stream": true
}
```

## Parallel Tool Calls

When `parallel_tool_calls: true` (default), the model can call multiple functions:

```json
{
  "output": [
    {"type": "message", ...},
    {
      "type": "function_call",
      "name": "get_weather",
      "arguments": "{\"location\":\"Boston\"}"
    },
    {
      "type": "function_call", 
      "name": "get_weather",
      "arguments": "{\"location\":\"Seattle\"}"
    }
  ]
}
```

Each tool call has:
- Unique `call_id`
- Unique `output_index` (1, 2, 3, ...)
- Separate event streams

## Output Item Types

### Message (index 0)
```json
{
  "type": "message",
  "role": "assistant",
  "content": [{"type": "output_text", "text": "..."}]
}
```

### Function Call (index 1+)
```json
{
  "type": "function_call",
  "call_id": "call_xyz",
  "name": "get_weather",
  "arguments": "{...}"
}
```

## Implementation Details

### Backend Translation

The proxy translates between formats:

**Responses API → Chat Completions:**
- `tools` array → `tools` array (function type only)
- `tool_choice` → `tool_choice`
- `parallel_tool_calls` → `parallel_tool_calls`
- `function_call` input → assistant message with `tool_calls`
- `function_call_output` input → `tool` role message

**Chat Completions → Responses API:**
- Delta `tool_calls` → `function_call_arguments.delta` events
- Complete tool calls → `function_call` output items
- Maintains proper `output_index` ordering

### State Tracking

For each tool call, the proxy tracks:
- `id` - Call identifier
- `type` - Always "function" currently
- `name` - Function name
- `arguments` - Accumulated JSON arguments
- `item_added` - Whether output_item.added was sent

### Event Sequencing

Events are numbered sequentially:
1. `response.created`
2. `response.output_item.added` (message)
3. `response.content_part.added` (message text)
4. Multiple `response.output_text.delta` (text chunks)
5. `response.output_item.added` (function call)
6. Multiple `response.function_call_arguments.delta` (args chunks)
7. `response.function_call_arguments.done`
8. `response.output_item.done` (function call)
9. `response.output_text.done`
10. `response.output_item.done` (message)
11. `response.completed`

## Examples

See:
- `tests/manual/tool_calling_simple.py` - Python streaming example
- `tests/manual/tool_calling_example.sh` - Multi-turn bash example
- `test_tool_calling.sh` - Test suite with multiple scenarios

## Limitations

**Currently supported:**
- Function tools only (not file_search, web_search, code_interpreter, etc.)
- Stateless operation (no conversation persistence)
- Tool calls from model to client

**Not yet supported:**
- Built-in tools (file_search, web_search, etc.) - filtered out
- Custom tool types
- Tool call cancellation
- Background responses with tools

## Testing

Run tool calling tests:
```bash
./test_tool_calling.sh
```

Run specific test:
```bash
python tests/manual/tool_calling_simple.py
```

## Debugging

Enable debug logging to see tool call processing:
```bash
RUST_LOG=debug cargo run
```

Look for log messages:
- `🔧 Tool call started: <name> (index <N>)`
- `🔧 Tool call complete: <name> - <bytes> bytes of args`
- `🔧 INPUT: Found function_call (<name>) - will attach to assistant message`
- `🔧 INPUT: Added function_call_output (call_id: <id>)`

## Architecture

```
Client Request (Responses API with tools)
         ↓
   Request Parser
         ↓
   Tool Definitions → Chat Completions format
         ↓
   Backend (Chutes.ai)
         ↓
   Streaming Response Parser
         ↓
   Tool Call State Tracker (HashMap)
         ↓
   Event Generator:
   - output_item.added (function_call)
   - function_call_arguments.delta
   - function_call_arguments.done
   - output_item.done (function_call)
         ↓
   SSE Stream to Client
```

## Performance

- **Overhead:** 1-2ms for tool call event generation
- **Memory:** ~200 bytes per tool call state
- **Streaming:** No buffering, events sent as received
- **Parallel calls:** Handled efficiently with HashMap tracking

## Error Handling

If backend returns malformed tool calls:
- Invalid JSON in arguments → logged but passed through
- Missing fields → defaults applied
- Tool call errors → logged, response continues

Circuit breaker applies to tool calling requests same as regular requests.


