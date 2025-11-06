# Docker Deployment Guide

## Quick Start

```bash
# Setup environment
cp .env.sample .env

# Start services
docker compose up -d

# Check status
docker compose ps
docker compose logs -f
```

## Architecture

```
Internet
   ↓
Caddy (Port 443) - Auto-HTTPS with Let's Encrypt
   ↓
OpenAI Responses Proxy (Port 8282)
   ↓
Chutes.ai Backend
```

## Services

### openai-responses-proxy

**Container:** `openai-responses-proxy`
**Port:** 8282 (internal), configurable via `HOST_PORT`
**Health:** `/health` endpoint

**Environment:**
- `BACKEND_URL` - Chutes.ai backend
- `HOST_PORT` - Listen port
- `RUST_LOG` - Log level
- `BACKEND_TIMEOUT_SECS` - Request timeout

### caddy

**Container:** `responses-proxy-caddy`
**Ports:** 443 (HTTPS), 80 (HTTP/ACME)

**Environment:**
- `CADDY_DOMAIN` - Your domain (e.g., responses-proxy.chutes.ai)
- `CADDY_PORT` - HTTPS port (default: 443)
- `CADDY_TLS` - Enable auto-HTTPS (default: true)

**Volumes:**
- `caddy_data` - TLS certificates
- `caddy_config` - Caddy configuration

## Production Deployment

### Prerequisites

1. **Server with public IP**
2. **Domain name** pointing to server
3. **Ports 80 and 443** open in firewall
4. **Docker and Docker Compose** installed

### Setup

1. **Clone repository:**
```bash
git clone <repo>
cd responses-proxy
```

2. **Configure environment:**
```bash
cp .env.sample .env
nano .env  # Edit settings
```

Example `.env` for production:
```bash
# Backend
BACKEND_URL=https://llm.chutes.ai/v1/chat/completions
BACKEND_TIMEOUT_SECS=600

# Proxy
HOST_PORT=8282
RUST_LOG=info

# Caddy - UPDATE THIS
CADDY_DOMAIN=responses-proxy.chutes.ai
CADDY_PORT=443
CADDY_TLS=true
```

3. **Deploy:**
```bash
docker compose up -d
```

4. **Verify:**
```bash
# Check containers
docker compose ps

# Check logs
docker compose logs -f

# Test health
curl https://responses-proxy.chutes.ai/health
```

## Local Development

For local testing without TLS:

```bash
# .env
CADDY_DOMAIN=localhost
CADDY_PORT=8180
CADDY_TLS=false
HOST_PORT=8282

# Start
docker compose up -d

# Test
curl http://localhost:8180/health
```

## SSL/TLS Configuration

### Automatic HTTPS (Default)

Caddy automatically obtains Let's Encrypt certificates when:
- `CADDY_TLS=true`
- DNS points domain to server
- Ports 80 and 443 are accessible
- Domain is valid (not localhost, not IP)

**Certificate storage:** `/data/caddy/` in `caddy_data` volume

### Manual Certificate

To use custom certificates:

1. **Add volume mount in docker compose.yaml:**
```yaml
volumes:
  - ./certs:/certs:ro
```

2. **Update Caddyfile:**
```caddyfile
{$CADDY_DOMAIN:}:{$CADDY_PORT:443} {
    tls /certs/cert.pem /certs/key.pem
    reverse_proxy openai-responses-proxy:{$HOST_PORT:8282}
}
```

### Disable TLS (HTTP Only)

```bash
# .env
CADDY_TLS=false
CADDY_PORT=8180

# Restart
docker compose restart caddy
```

## Container Management

### Start services
```bash
docker compose up -d
```

### Stop services
```bash
docker compose down
```

### Restart specific service
```bash
docker compose restart openai-responses-proxy
docker compose restart caddy
```

### View logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f openai-responses-proxy
docker compose logs -f caddy
```

### Update and redeploy
```bash
git pull
docker compose build
docker compose up -d
```

## Monitoring

### Health Checks

**Via Caddy (production):**
```bash
curl https://responses-proxy.chutes.ai/health
```

**Direct to proxy:**
```bash
curl http://localhost:8282/health
```

**Expected response:**
```json
{
  "status": "healthy",
  "circuit_breaker": {
    "enabled": true,
    "is_open": false,
    "consecutive_failures": 0
  }
}
```

### Logs

**Structured logging:**
```bash
docker compose logs -f openai-responses-proxy | grep "request_completed"
```

**Error logs:**
```bash
docker compose logs openai-responses-proxy | grep ERROR
```

## Troubleshooting

### Caddy not getting certificate

1. **Check DNS:**
```bash
nslookup responses-proxy.chutes.ai
# Should point to your server IP
```

2. **Check ports:**
```bash
netstat -tulpn | grep :443
netstat -tulpn | grep :80
```

3. **Check Caddy logs:**
```bash
docker compose logs caddy | grep -i acme
docker compose logs caddy | grep -i cert
```

4. **Verify domain is reachable:**
```bash
curl -I http://responses-proxy.chutes.ai
```

### Proxy not responding

1. **Check container status:**
```bash
docker compose ps
```

2. **Check health endpoint:**
```bash
docker compose exec openai-responses-proxy curl http://localhost:8282/health
```

3. **Check logs:**
```bash
docker compose logs --tail=100 openai-responses-proxy
```

### Backend connection issues

1. **Test backend directly:**
```bash
docker compose exec openai-responses-proxy curl -I https://llm.chutes.ai/v1/models
```

2. **Check timeout settings:**
```bash
docker compose exec openai-responses-proxy env | grep TIMEOUT
```

## Performance Tuning

### Resource Limits

Add to docker compose.yaml:

```yaml
services:
  openai-responses-proxy:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 256M
```

### Caddy Tuning

For high traffic, increase Caddy connection limits in Caddyfile:

```caddyfile
{
    max_conns 10000
}

{$CADDY_DOMAIN:}:{$CADDY_PORT:443} {
    reverse_proxy openai-responses-proxy:{$HOST_PORT:8282} {
        transport http {
            keepalive 90s
            keepalive_idle_conns 100
        }
    }
}
```

## Security

### Firewall Rules

**Production:**
- Allow: 80 (HTTP - ACME only)
- Allow: 443 (HTTPS)
- Block: 8282 (proxy port - internal only)

**UFW Example:**
```bash
ufw allow 80/tcp
ufw allow 443/tcp
ufw deny 8282/tcp  # Internal only
```

### API Key Security

- Keys forwarded to backend (not stored)
- Keys masked in logs
- No key caching or persistence

### Network Isolation

Use Docker networks to isolate proxy from internet:

```yaml
services:
  openai-responses-proxy:
    networks:
      - internal
      
  caddy:
    networks:
      - internal
      - public

networks:
  internal:
    internal: true
  public:
```

## Backup and Recovery

### Backup Caddy certificates

```bash
# Backup
docker run --rm -v responses-proxy_caddy_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/caddy-data-backup.tar.gz /data

# Restore
docker run --rm -v responses-proxy_caddy_data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/caddy-data-backup.tar.gz -C /
```

### Disaster Recovery

1. **Redeploy on new server:**
```bash
git clone <repo>
cd responses-proxy
cp .env.sample .env
# Edit .env
docker compose up -d
```

2. **Caddy will auto-obtain new certificates** (Let's Encrypt)

## Updates

### Update proxy code

```bash
git pull
docker compose build openai-responses-proxy
docker compose up -d openai-responses-proxy
```

### Update Caddy

```bash
docker compose pull caddy
docker compose up -d caddy
```

### Update both

```bash
git pull
docker compose build
docker compose pull
docker compose up -d
```

