# Deployment Guide

## Quick Start

### Local Development

```bash
# Clone and build
git clone <repo>
cd responses-proxy
cargo build --release

# Configure
cp .env.example .env
# Edit .env with your settings

# Run
./target/release/openai_responses_proxy
```

### Docker

```bash
# Build and run with docker compose
docker compose up -d

# Or build manually
docker build -t openai-responses-proxy .
docker run -p 8282:8282 \
  -e BACKEND_URL=https://llm.chutes.ai/v1/chat/completions \
  -e RUST_LOG=info \
  openai-responses-proxy
```

### Production Deployment

**Recommended setup:**

1. **Reverse Proxy** - Use nginx/Caddy for SSL/TLS
2. **Process Manager** - Use systemd or Docker
3. **Monitoring** - Monitor `/health` endpoint
4. **Logging** - Set `RUST_LOG=info` for production

**Systemd Service:**

```ini
[Unit]
Description=OpenAI Responses Proxy
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/openai-responses-proxy
Environment="BACKEND_URL=https://llm.chutes.ai/v1/chat/completions"
Environment="HOST_PORT=8282"
Environment="RUST_LOG=info"
ExecStart=/opt/openai-responses-proxy/openai_responses_proxy
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Nginx Configuration:**

```nginx
upstream responses_proxy {
    server 127.0.0.1:8282;
    keepalive 32;
}

server {
    listen 443 ssl http2;
    server_name api.yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location /v1/responses {
        proxy_pass http://responses_proxy;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # SSE specific
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 600s;
        chunked_transfer_encoding on;
    }

    location /health {
        proxy_pass http://responses_proxy;
    }
}
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND_URL` | `https://llm.chutes.ai/v1/chat/completions` | Chutes.ai backend URL |
| `HOST_PORT` | `8282` | Port to listen on |
| `RUST_LOG` | `info` | Log level (error, warn, info, debug, trace) |
| `BACKEND_TIMEOUT_SECS` | `600` | Backend request timeout |

## Monitoring

**Health Check:**
```bash
curl http://localhost:8282/health
```

**Expected response:**
```json
{
  "status": "healthy",
  "circuit_breaker": {
    "enabled": false,
    "is_open": false,
    "consecutive_failures": 0
  }
}
```

**Metrics Logging:**

Enable structured metrics with `RUST_LOG=info`:

```
INFO metrics: request_completed: model=gpt-4o, duration_ms=1234, status=completed
```

## Security

1. **API Key Handling**
   - Proxy forwards client keys to backend
   - Keys are masked in logs (only first 6 and last 4 chars shown)
   - No keys stored or cached

2. **Request Validation**
   - Content size limits (10MB max)
   - Header validation
   - Model name validation

3. **Rate Limiting**
   - Implement at reverse proxy level (nginx, Caddy)
   - Backend rate limits apply

## Troubleshooting

### High Latency

1. Check backend connectivity
2. Review `BACKEND_TIMEOUT_SECS` setting
3. Monitor circuit breaker status
4. Check network between proxy and backend

### Memory Issues

1. SSE buffer is bounded at 1MB
2. Connection pooling limited to 1024 per host
3. No conversation state stored (stateless)

### Authentication Errors

1. Verify API key format
2. Check key is being forwarded: `RUST_LOG=debug`
3. Test backend directly to isolate issue

### Circuit Breaker Open

1. Check backend health
2. Review recent error logs
3. Wait 30s for auto-recovery
4. Restart proxy if needed

## Performance Tuning

**Connection Pool:**
- Default: 1024 connections per host
- Adjust in `main.rs` if needed

**Timeouts:**
- Connect: 10s (hardcoded)
- Request: 600s (configurable via `BACKEND_TIMEOUT_SECS`)

**Buffer Sizes:**
- SSE buffer: 1MB max (prevents memory exhaustion)
- Channel size: 64 events (streaming)

## Scaling

**Horizontal Scaling:**
- Proxy is stateless - scale horizontally
- Use load balancer (nginx, HAProxy, etc.)
- Each instance independent

**Vertical Scaling:**
- Async I/O scales well with cores
- Memory usage: ~50MB base + 1MB per active request
- CPU: Minimal overhead (~1% for format conversion)

## Development

**Run in development mode:**
```bash
RUST_LOG=debug cargo run
```

**Build optimized binary:**
```bash
cargo build --release
strip target/release/openai_responses_proxy  # Optional: reduce size
```

**Run tests:**
```bash
./test_proxy.sh
```

