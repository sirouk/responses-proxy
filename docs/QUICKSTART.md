# Quick Start Guide

## 1. Setup Environment

```bash
cd /root/responses-proxy
cp .env.sample .env
```

Edit `.env` and set:
```bash
CADDY_DOMAIN=responses-proxy.chutes.ai
ENABLE_LOG_VOLUME=false  # enable only when you need on-disk dumps
```

## 2. Deploy

```bash
./deploy.sh
```

This will:
- Build the Docker containers
- Start the proxy and Caddy
- Configure auto-HTTPS
- Run health checks

## 3. Verify

```bash
# Check services are running
docker compose ps

# Test health endpoint
curl http://localhost:8282/health

# View logs
docker compose logs -f
```

## 4. Test the Proxy

**Simple request:**
```bash
curl -N https://responses-proxy.chutes.ai/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer cpk_your_api_key" \
  -d '{
    "model": "gpt-4o",
    "input": "Say hello",
    "stream": true
  }'
```

**Expected output:**
```
data: {"type":"response.created",...}

data: {"type":"response.output_item.added",...}

data: {"type":"response.output_text.delta","delta":"Hello",...}

data: {"type":"response.completed",...}
```

## 5. Stop Services

```bash
docker compose down
```

Or keep running and restart containers:
```bash
docker compose restart
```

## Configuration Options

### Development (HTTP, no TLS)

```bash
# .env
CADDY_TLS=false
CADDY_PORT=8180
CADDY_DOMAIN=localhost

# Deploy
./deploy.sh

# Access
curl http://localhost:8180/v1/responses \
  -H "Authorization: Bearer cpk_test" \
  -d '{"model":"gpt-4o","input":"test"}'
```

### Production (HTTPS, auto-certificates)

```bash
# .env
CADDY_TLS=true
CADDY_PORT=443
CADDY_DOMAIN=responses-proxy.chutes.ai

# Deploy
./deploy.sh

# Access
curl https://responses-proxy.chutes.ai/v1/responses \
  -H "Authorization: Bearer cpk_your_key" \
  -d '{"model":"gpt-4o","input":"test"}'
```

## Monitoring

**View live logs:**
```bash
docker compose logs -f openai-responses-proxy
```

> ℹ️ Keep `ENABLE_LOG_VOLUME=false` in most environments so the proxy avoids writing request bodies to disk. Enable it temporarily only when you need detailed dumps in `LOG_DIR`.

**Check metrics:**
```bash
docker compose logs openai-responses-proxy | grep "request_completed"
```

**Health status:**
```bash
watch -n 5 'curl -s http://localhost:8282/health | jq'
```

## Troubleshooting

**Problem:** Can't reach https://responses-proxy.chutes.ai

**Solution:**
1. Check DNS: `nslookup responses-proxy.chutes.ai`
2. Check ports: `netstat -tulpn | grep -E ':80|:443'`
3. Check Caddy logs: `docker compose logs caddy`
4. Test direct: `curl http://localhost:8282/health`

**Problem:** Certificate errors

**Solution:**
1. Wait 1-2 minutes for certificate acquisition
2. Check Caddy logs for ACME errors
3. Verify DNS is correct
4. Ensure ports 80 and 443 are open

**Problem:** Backend errors

**Solution:**
1. Check backend URL: `echo $BACKEND_URL`
2. Test backend: `curl https://llm.chutes.ai/v1/models`
3. Check API key is valid
4. Review proxy logs: `docker compose logs openai-responses-proxy`

## Next Steps

- Review [API_REFERENCE.md](docs/API_REFERENCE.md) for API details
- Check [DOCKER.md](docs/DOCKER.md) for advanced deployment
- See `tests/manual/` for runnable client samples
- Read [DEPLOYMENT.md](docs/DEPLOYMENT.md) for production setup

