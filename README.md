# OpenAI Responses Proxy for Chutes.ai

Production-grade Rust service translating the OpenAI Responses API into a Chat Completions request for Chutes.ai backends. Ships with streaming, tool calling, reasoning support, and operational tooling sized for live traffic.

## Highlights

- **Full Responses API surface**: text, multimodal inputs, streamed outputs, tool calling.
- **Stateless transformer**: forwards client auth, keeps no session state, easy to scale.
- **Safe defaults**: request validation, circuit breaker guard, bounded logging.
- **Observability hooks**: structured logging, optional on-disk dumps, metrics-friendly event stream.

## Lightning Quick Start

Bootstrap the Chutes.ai Codex fork, config, and credential helper in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/chutesai/responses-proxy/refs/heads/main/install_codex.sh | bash
```

The script installs Rust if needed, builds the forked Codex CLI, offers to replace any existing `codex`, and writes the recommended `config.toml` plus API-key helper.

For deeper background, see the companion docs in `docs/` (e.g. `docs/PROJECT_SUMMARY.md`).

## Quick Start (Codex Client)

1. **Configure Codex (OpenAI)** – add to your profile (`~/.codex/config.toml`):

   ```toml
   # Global
   model_provider = "chutes-ai"
   model = "Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8"
   # model = "openai/gpt-4o-mini"
   model_reasoning_effort = "high"

   [model_providers."chutes-ai"]
   name = "Chutes AI via responses proxy"
   base_url = "https://responses.chutes.ai/v1"
   env_key = "MY_PROVIDER_API_KEY"
   wire_api = "responses"

   [notice]
   hide_full_access_warning = true

   [features]
   #apply_patch_freeform = true
   view_image_tool = true
   web_search_request = true

   [experimental]
   #unified_exec = true
   #streamable_shell = true
   #experimental_sandbox_command_assessment = true
   rmcp_client = true                           # Rust MCP client
   ```

2. **Export your API key** (matches `env_key`):

   ```bash
   export MY_PROVIDER_API_KEY="cpk_xxx"   # example key
   ```

3. **Start a Codex session**:

   ```bash
   codex
   ```

   Pick the `chutes-ai` provider inside the UI; requests will flow through `https://responses.chutes.ai/v1`.

> ℹ️ Only `function` tools are forwarded; Codex options such as `web_search_request` may fall back gracefully if the backend rejects them. Reasoning effort hints are passed through to the backend model.

## Codex Configuration

The example excerpt for Codex (OpenAI) config.toml should be carefully adjusted to your needs:


- Keep `env_key` synced with an environment variable that stores your Chutes-compatible API token.
- The proxy only supports function tools; Codex options such as `web_search_request` may trigger warnings because the backend drops non-function tools.
- Reasoning effort hints are forwarded, but final behaviour depends on the selected model.

## Configuration

Environment variables (see `docs/QUICKSTART.md` for exhaustive notes):

| Variable | Default | Purpose |
| --- | --- | --- |
| `BACKEND_URL` | `https://llm.chutes.ai/v1/chat/completions` | Target Chat Completions endpoint |
| `BACKEND_TIMEOUT_SECS` | `600` | Total request timeout against backend |
| `HOST_PORT` | `8282` | Axum listener port |
| `RUST_LOG` | `info` | Log level (`error`…`trace`) |
| `ENABLE_LOG_VOLUME` | `false` | When `true`, dumps requests/streams to `LOG_DIR` |
| `LOG_DIR` | `logs` | Base directory for optional dumps |
| `CADDY_DOMAIN` | `responses.chutes.ai` | TLS host for Caddy deployment |
| `CADDY_PORT` | `443` | Exposed HTTPS port |

Logging dumps are gated behind `ENABLE_LOG_VOLUME`; with the flag disabled the proxy never writes request or stream bodies to disk.

## API Surface

- `POST /v1/responses` – Accepts OpenAI Responses payloads, streams SSE events.
- `GET /health` – Reports circuit breaker status and readiness for load balancers.

Key behaviours:

- **Request validation**: size limits on inputs, instructions, and tool counts.
- **Tool support**: forwards `function` tools, injects missing file utilities for external providers, and converts stray XML-style tool call text into native function events.
- **Reasoning models**: captures `reasoning_content`, emits `<think>`-compatible events, and surfaces reasoning output items alongside final content.
- **Responses parity**: accepts modern Responses parameters like `include`, `stream_options`, `text.format`, `top_logprobs`, and `user`, forwarding structured-output formats and logprob hints to the backend while warning (or rejecting) unsupported knobs such as `background`, `prompt` templates, and `service_tier`.
- **File inputs**: rejects `input_file` content parts with a clear error because the Chat Completions backend cannot dereference OpenAI file IDs; clients must inline file contents before sending.
- **No persistence**: the optional `store` flag is accepted but ignored; a warning is logged when provided.

## Operational Notes

- Circuit breaker guards backend outages (5 failures → 30s cool-down).
- Model list cached in-memory and refreshed every 60 s; casing normalized automatically.
- Background tasks shut down gracefully on `SIGINT`/`ctrl+c`.
- IDs for streamed items incorporate the request identifier to prevent cross-request collisions.

## Related Documentation

- `docs/QUICKSTART.md` – environment setup and deployment walkthroughs.
- `docs/TOOL_CALLING.md` – in-depth description of tool conversion and streaming semantics.
- `docs/REASONING_SUPPORT.md` – handling reasoning content and `<think>` emission.
- `docs/TESTING.md` – regression scripts and smoke checks.
- `docs/IMPLEMENTATION_NOTES.md` – architecture and internal invariants.

Keep docs authoritative: update both this README and the relevant `docs/*` reference when behaviour changes.

