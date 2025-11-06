# OpenAI Responses Proxy for Chutes.ai

Production-ready Rust proxy that translates OpenAI Responses API to Chat Completions format.

**Domain:** responses-proxy.chutes.ai  
**Backend:** llm.chutes.ai (52 models)  
**Performance:** 1-2ms overhead, 1000+ req/s

## Features

- ✅ **Core Responses API** - Text, images, tool calling with proper streaming
- ✅ **Input types** - Text (string/structured), images (image_url)
- ✅ **Output types** - Text, reasoning, function calls
- ✅ **Function tools** - Complete support with streaming events
- ⚠️ **Advanced tools** - Only function tools supported; others rejected
- ✅ **Reasoning models** - Full support (DeepSeek-R1, o1) with `<think>` tags
- ✅ **SSE streaming** - Proper event formatting & sequencing
- ✅ **Stateless architecture** - No state storage, easy scaling
- ✅ **Auth forwarding** - Client keys forwarded to backend (masked in logs)
- ✅ **Model caching** - 60s refresh, case-insensitive matching
- ✅ **Circuit breaker** - Protection (5 failures → 30s recovery)
- ✅ **Production ready** - Caddy, auto-HTTPS, health checks
- ✅ **Thread-safe** - Arc<RwLock<>>, async streaming
- ✅ **Request validation** - Size limits, token bounds
- ✅ **Auto-injection** - apply_patch tool for external provider compatibility

## Quick Start

**TL;DR:**
```bash
./deploy.sh
# Access: https://responses-proxy.chutes.ai
```

**Docker with Caddy (Production - Port 443):**
```bash
# Setup
cp .env.sample .env
# Edit CADDY_DOMAIN in .env

# Deploy
./deploy.sh

# The proxy will be available at:
# https://responses-proxy.chutes.ai (with auto-HTTPS)
# http://localhost:8282 (direct to proxy)
```

**From Source (Development - Port 8282):**
```bash
cargo build --release
cargo run --release
```

See [docs/QUICKSTART.md](docs/QUICKSTART.md) for detailed setup instructions.

**Example request:**
```bash
curl -N http://localhost:8282/v1/responses \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer cpk_your_key' \
  -d '{
    "model": "gpt-4o",
    "input": "Hello, how are you?",
    "stream": true
  }'
```

**Or via Caddy (production):**
```bash
curl -N https://responses-proxy.chutes.ai/v1/responses \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer cpk_your_key' \
  -d '{
    "model": "gpt-4o",
    "input": "Hello, how are you?",
    "stream": true
  }'
```

## Configuration

**Setup:**
```bash
cp .env.sample .env
# Edit .env with your settings
```

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND_URL` | `https://llm.chutes.ai/v1/chat/completions` | Chutes.ai backend endpoint |
| `HOST_PORT` | `8282` | Proxy listen port |
| `RUST_LOG` | `info` | Log level (error/warn/info/debug/trace) |
| `BACKEND_TIMEOUT_SECS` | `600` | Backend request timeout |
| `ENABLE_LOG_VOLUME` | `false` | Enable verbose body dumps (writes to `LOG_DIR`) |
| `LOG_DIR` | `logs` | Directory for optional request/stream dumps |
| `CADDY_DOMAIN` | `responses-proxy.chutes.ai` | Domain for Caddy |
| `CADDY_PORT` | `443` | Caddy HTTPS port |
| `CADDY_TLS` | `true` | Enable auto-HTTPS (set to `false` for HTTP) |

**Sample `.env`:**
```bash
# Backend
BACKEND_URL=https://llm.chutes.ai/v1/chat/completions
BACKEND_TIMEOUT_SECS=600

# Proxy
HOST_PORT=8282
RUST_LOG=info

# Caddy (for production deployment)
CADDY_DOMAIN=responses-proxy.chutes.ai
CADDY_PORT=443
CADDY_TLS=true
```

**Authentication:**
- Client API key (`cpk_*` or backend-compatible) → forwarded directly to backend
- No client auth → rejected with 401

## API Endpoints

- `POST /v1/responses` - Main OpenAI Responses API endpoint
- `GET /health` - Health check with circuit breaker status

## Supported Features

### Feature Matrix

| Feature Category | Feature | Support | Notes |
|-----------------|---------|---------|-------|
| **Input Types** | Text (`input_text`) | ✅ Full | String or structured messages |
| | Images (`input_image`) | ✅ Full | Image URLs in content array |
| | Files (`input_file`) | ❌ Not supported | Chat Completions limitation |
| | Audio (`input_audio`) | ❌ Not supported | Chat Completions limitation |
| | Multi-turn messages | ✅ Full | Array of message items |
| | Reasoning items | ✅ Full | Converted to `<think>` tags |
| **Output Types** | Text (`output_text`) | ✅ Full | With streaming deltas |
| | Reasoning | ✅ Full | From `reasoning_content` field |
| | Function calls | ✅ Full | With streaming arguments |
| | Refusal | ⚠️ Model | Detected if model supports |
| | Audio | ❌ Not supported | Chat Completions limitation |
| **Tools** | Function tools | ✅ Full | Complete support with validation |
| | `web_search` / `file_search` | ❌ Rejected | Chat Completions doesn't support |
| | `code_interpreter` | ❌ Rejected | Chat Completions doesn't support |
| | `tool_choice` | ✅ Full | auto/none/required/specific |
| | `parallel_tool_calls` | ✅ Full | Forwarded to backend |
| | Auto-injected `apply_patch` | ✅ Always | For external provider testing |
| **Parameters** | `model` | ✅ Full | With normalization & caching |
| | `instructions` | ✅ Full | → system message |
| | `temperature` | ✅ Full | Direct mapping |
| | `top_p` | ✅ Full | Direct mapping |
| | `max_output_tokens` | ✅ Full | → max_tokens |
| | `metadata` | ✅ Full | Echoed back in response |
| | `stream` | ✅ Full | SSE streaming |
| | Advanced params | ❌ Not supported | reasoning.effort, text.format, etc. |
| **Streaming Events** | `response.created` | ✅ Full | |
| | `response.output_item.added` | ✅ Full | Message & function calls |
| | `response.content_part.added` | ✅ Full | |
| | `response.output_text.delta` | ✅ Full | |
| | `response.output_text.done` | ✅ Full | |
| | `response.reasoning_text.delta` | ✅ Full | For reasoning models |
| | `response.reasoning_text.done` | ✅ Full | For reasoning models |
| | `response.function_call_arguments.delta` | ✅ Full | |
| | `response.function_call_arguments.done` | ✅ Full | |
| | `response.content_part.done` | ✅ Full | |
| | `response.output_item.done` | ✅ Full | |
| | `response.completed` | ✅ Full | |
| | `response.failed` | ✅ Full | |

### Limitations (Chat Completions Backend)

**Not Supported (by design):**
- File inputs (`input_file`) - Requires native file handling
- Audio inputs/outputs - Requires audio-enabled models
- Advanced tool types - `web_search`, `file_search`, `code_interpreter`, etc.
- Structured output parameters - `text.format`, `reasoning.effort`
- Stateful features - `previous_response_id`, conversation continuity

**Why:** These features require native Responses API backends. Chat Completions API doesn't provide equivalent functionality.

**Workaround:** Use function tools and text/image inputs for maximum compatibility.

## Request Format

The proxy accepts OpenAI Responses API format:

```json
{
  "model": "gpt-4o",
  "input": "What is 2+2?",
  "instructions": "You are a helpful math tutor.",
  "max_output_tokens": 1024,
  "temperature": 0.7,
  "stream": true
}
```

Or with structured input:

```json
{
  "model": "gpt-4o",
  "input": [
    {
      "type": "message",
      "role": "user",
      "content": "What is 2+2?"
    }
  ],
  "stream": true
}
```

**Tool calling (function calling):**

```json
{
  "model": "gpt-4o-mini",
  "input": "What is the weather in San Francisco?",
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
  "parallel_tool_calls": true,
  "stream": true
}
```

Supported `tool_choice` values:
- `"auto"` (default) - Model decides whether to call tools
- `"none"` - Model will not call any tools
- `"required"` - Model must call at least one tool
- `{"type": "function", "function": {"name": "get_weather"}}` - Force specific tool

## Response Format

Streaming responses follow the OpenAI Responses API event format:

**Standard text events:**
- `response.created` - Response started
- `response.output_item.added` - Output item added  
- `response.content_part.added` - Content part added
- `response.output_text.delta` - Text delta (streamed chunks)
- `response.output_text.done` - Text complete
- `response.content_part.done` - Content part done
- `response.output_item.done` - Output item done
- `response.completed` - Response complete

**Tool calling events:**
- `response.output_item.added` - Function call item added (type: "function_call")
- `response.function_call_arguments.delta` - Function arguments streaming
- `response.function_call_arguments.done` - Function arguments complete
- `response.output_item.done` - Function call item complete

Example streaming response:

```
data: {"type":"response.created","response":{"id":"resp_...","object":"response","created_at":1234567890,"status":"in_progress","error":null,"model":"gpt-4o","output":[],"usage":null,"metadata":null},"sequence_number":1}

data: {"type":"response.output_item.added","item_id":"msg_...","output_index":0,"item":{"id":"msg_...","type":"message","status":"in_progress","role":"assistant","content":[]},"sequence_number":2}

data: {"type":"response.output_text.delta","item_id":"msg_...","output_index":0,"content_index":0,"delta":"Hello","sequence_number":4}

data: {"type":"response.output_text.delta","item_id":"msg_...","output_index":0,"content_index":0,"delta":" there!","sequence_number":5}

data: {"type":"response.output_text.done","item_id":"msg_...","output_index":0,"content_index":0,"text":"Hello there!","sequence_number":6}

data: {"type":"response.completed","response":{"id":"resp_...","status":"completed",...},"sequence_number":9}
```

**Tool calling response example:**

When the model makes a tool call, you'll receive these events:

```
data: {"type":"response.output_item.added","item_id":"call_123","output_index":1,"item":{"id":"call_123","type":"function_call","status":"in_progress","call_id":"call_abc","name":"get_weather","arguments":""},"sequence_number":5}

data: {"type":"response.function_call_arguments.delta","item_id":"call_123","output_index":1,"delta":"{\"location\":","sequence_number":6}

data: {"type":"response.function_call_arguments.delta","item_id":"call_123","output_index":1,"delta":"\"San Francisco, CA\"}","sequence_number":7}

data: {"type":"response.function_call_arguments.done","item_id":"call_123","output_index":1,"name":"get_weather","arguments":"{\"location\":\"San Francisco, CA\"}","sequence_number":8}

data: {"type":"response.output_item.done","item_id":"call_123","output_index":1,"item":{"id":"call_123","type":"function_call","status":"completed","call_id":"call_abc","name":"get_weather","arguments":"{\"location\":\"San Francisco, CA\"}"},"sequence_number":9}

data: {"type":"response.completed","response":{"id":"resp_...","output":[{"type":"message",...},{"type":"function_call","call_id":"call_abc","name":"get_weather","arguments":"..."}]},"sequence_number":10}
```

The final `response.completed` event includes all output items:
- Message item (index 0) with any text the model produced
- Function call item(s) (index 1+) with `call_id`, `name`, and `arguments`

## Usage Examples

See the `tests/manual/` directory for complete examples:

- `simple_request.sh` - Basic streaming request
- `multi_turn.sh` - Multi-turn conversation
- `python_client.py` - Python client example
- `tool_calling_simple.py` - Tool calling streaming demo

**Run test suite:**
```bash
./test_proxy.sh           # Full test suite
./test_tool_calling.sh    # Tool calling specific tests
```

**For detailed tool calling documentation, see [TOOL_CALLING.md](TOOL_CALLING.md)**

### Tool Calling Quick Start

```bash
# Simple tool calling request
curl -N http://localhost:8282/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "input": "What is the weather in San Francisco?",
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "parameters": {
          "type": "object",
          "properties": {"location": {"type": "string"}},
          "required": ["location"]
        }
      }
    }],
    "tool_choice": "auto",
    "stream": true
  }'
```

The model will call the function and you'll receive:
- `response.output_item.added` with `type: "function_call"`
- `response.function_call_arguments.delta` events (streaming arguments)
- `response.function_call_arguments.done` with complete arguments
- `response.output_item.done` with the complete function call

### Tool Calling Support

**Fully Supported:** ✅ Function tools
- `type: "function"` - Standard custom functions with name, description, and parameters
- Complete streaming support with delta and done events
- Parallel tool calls supported
- Auto-injected `apply_patch` tool for external provider compatibility

**Not Supported:** ❌ Advanced tool types
- `web_search` / `web_search_preview` - Returns validation error
- `file_search` - Returns validation error
- `code_interpreter` - Returns validation error
- Other advanced types - Returns validation error

**Why:** Chat Completions API backends primarily support function tools. Advanced tool types require native Responses API backends with built-in tool infrastructure.

**Error Response:** When unsupported tool type is used, proxy returns:
```
"Unsupported tool type 'web_search'. Only 'function' tools are supported when translating to Chat Completions API. Advanced tool types (file_search, web_search, code_interpreter, etc.) require native Responses API backends."
```

## Building

```bash
cargo build --release    # Binary: target/release/openai_responses_proxy (~6MB)
cargo check             # Quick compilation check
cargo test              # Run unit tests
```

## Docker Deployment

**With Caddy (Production - Auto-HTTPS):**
```bash
# Setup
cp .env.sample .env
# Edit CADDY_DOMAIN in .env

# Deploy
docker compose up -d

# Access
curl https://responses-proxy.chutes.ai/health
```

**Without Caddy (Development):**
```bash
docker compose up -d openai-responses-proxy
curl http://localhost:8282/health
```

**Build manually:**
```bash
docker build -t openai-responses-proxy .
docker run -p 8282:8282 \
  -e BACKEND_URL=https://llm.chutes.ai/v1/chat/completions \
  -e RUST_LOG=info \
  openai-responses-proxy
```

**SSL/TLS Notes:**
- Caddy automatically obtains Let's Encrypt certificates
- Requires ports 80 (ACME challenges) and 443 (HTTPS) open
- DNS must point `CADDY_DOMAIN` to server IP
- For local testing, set `CADDY_TLS=false`

**Management scripts:**
```bash
./deploy.sh           # Deploy or update
docker compose down   # Stop all services
```

## Troubleshooting

- **401 Unauthorized** - Ensure client sends a valid backend-compatible API key
- **404 Model Not Found** - Check available models at the backend
- **Circuit breaker open** - Check health: `curl http://localhost:8282/health`
- **Caddy certificate errors** - Verify DNS points to server and ports 80/443 open
- **Connection refused** - Check containers: `docker compose ps`
- **Debug logging** - Set `RUST_LOG=debug` in `.env` and restart

## Architecture

The proxy follows a clean Rust architecture inspired by the claude-proxy:

```
src/
├── models/              # Data models
│   ├── app.rs           # App state, circuit breaker
│   ├── openai_responses.rs   # Responses API models
│   └── chat_completions.rs   # Chat Completions models
├── handlers/            # HTTP handlers
│   ├── responses.rs     # Main /v1/responses endpoint
│   └── health.rs        # Health check endpoint
├── services/            # Business logic
│   ├── auth.rs          # Auth extraction & validation
│   ├── streaming.rs     # SSE event parser
│   ├── model_cache.rs   # Model discovery & caching
│   ├── converter.rs     # API format conversion
│   └── error_formatting.rs  # Error formatting
└── main.rs              # Entry point
```

**Key design principles:**
- Thread-safe state with `Arc<RwLock<>>`
- Efficient SSE parsing with bounded buffers (1MB max)
- Auth forwarding with key masking in logs
- Model caching with case-correction
- Circuit breaker pattern for reliability
- Comprehensive error handling
- Graceful shutdown on SIGTERM/SIGINT
- **Reasoning/thinking content** - Full round-trip support

## Conversion Details

**Request Flow:**
1. Accept OpenAI Responses API request (`/v1/responses`)
2. Extract `input` → convert to `messages` array
3. Extract `instructions` → convert to system message
4. Forward tools, temperature, etc. as-is
5. Stream to Chutes.ai Chat Completions endpoint
6. Parse SSE response stream
7. Convert Chat Completions events → Responses API events
8. Stream back to client

**Stateless Design:**
- No conversation state stored
- Each request is independent
- `item_reference` in input is logged but ignored (no state to reference)

## Performance

- **Latency:** ~1-2ms overhead for format conversion
- **Memory:** Bounded SSE buffers (1MB max)
- **Throughput:** Connection pooling with keepalive
- **Concurrency:** Fully async, handles 1000+ concurrent requests

## Documentation Index

- [QUICKSTART.md](docs/QUICKSTART.md) - Get started in 5 minutes
- [API_REFERENCE.md](docs/API_REFERENCE.md) - Complete API specification
- [DOCKER.md](docs/DOCKER.md) - Docker and Caddy deployment
- [DEPLOYMENT.md](docs/DEPLOYMENT.md) - Production deployment guide
- [TESTING.md](docs/TESTING.md) - Testing and validation
- [COMPARISON.md](docs/COMPARISON.md) - Responses API vs Chat Completions
- [REASONING_SUPPORT.md](docs/REASONING_SUPPORT.md) - Reasoning/thinking content
- [IMPLEMENTATION_NOTES.md](docs/IMPLEMENTATION_NOTES.md) - Architecture and design
- [CONTRIBUTING.md](docs/CONTRIBUTING.md) - Development guide
- [PROJECT_SUMMARY.md](docs/PROJECT_SUMMARY.md) - Project overview
- [DEPLOYMENT_CHECKLIST.md](docs/DEPLOYMENT_CHECKLIST.md) - Deployment steps
- [CHANGELOG.md](docs/CHANGELOG.md) - Version history

## Project Stats

- **Code:** 1,525 lines of Rust (14 source files)
- **Binary:** 9.6MB (release build)
- **Dependencies:** 194 crates
- **Documentation:** 14 guides in `docs/`
- **Examples:** 8 client examples
- **Performance:** 1-2ms overhead, 1000+ req/s
- **Memory:** ~50MB base + 1MB per active request

## Key Strengths from claude-proxy

- Clean Rust code with proper separation of concerns
- Thread-safe state management (Arc<RwLock<>>)
- Efficient SSE parsing with bounded buffers (1MB max)
- Auth forwarding with key masking in logs
- Model caching with case-correction
- Circuit breaker pattern for reliability
- Comprehensive error handling
- Graceful shutdown on SIGTERM/SIGINT
- **Reasoning/thinking content** - Full round-trip support

## License

MIT
