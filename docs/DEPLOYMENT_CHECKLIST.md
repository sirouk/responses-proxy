# Deployment Checklist for responses.chutes.ai

## Pre-Deployment

- [ ] Server provisioned with public IP
- [ ] Docker and Docker Compose installed
- [ ] Ports 80 and 443 open in firewall
- [ ] DNS A record: `responses.chutes.ai` → server IP
- [ ] API key obtained from Chutes.ai
- [ ] Repository cloned to server

## Configuration

- [ ] Copy `.env.sample` to `.env`
- [ ] Set `CADDY_DOMAIN=responses.chutes.ai` in `.env`
- [ ] Verify `BACKEND_URL=https://llm.chutes.ai/v1/chat/completions`
- [ ] Verify Caddyfile references correct container name

## Deployment

- [ ] Run `./deploy.sh`
- [ ] Check services: `docker compose ps` (both should be "Up")
- [ ] Check logs: `docker compose logs -f` (no errors)
- [ ] Wait 1-2 minutes for Caddy certificate acquisition

## Verification

- [ ] Health check (direct): `curl http://localhost:8282/health`
- [ ] Health check (via Caddy): `curl https://responses.chutes.ai/health`
- [ ] Test request (replace with real API key):
```bash
curl -N https://responses.chutes.ai/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer cpk_YOUR_KEY" \
  -d '{
    "model": "gpt-4o",
    "input": "Say hello",
    "stream": true,
    "max_output_tokens": 20
  }'
```

## Post-Deployment

- [ ] Verify TLS certificate: `curl -vI https://responses.chutes.ai 2>&1 | grep -i "subject\|issuer"`
- [ ] Test from external network
- [ ] Monitor logs for any errors: `docker compose logs -f`
- [ ] Set up monitoring/alerting (optional)
- [ ] Document API key for team
- [ ] Add to internal service catalog

## Maintenance

- [ ] Schedule regular updates: `git pull && docker compose build && docker compose up -d`
- [ ] Monitor disk space for logs: `docker system df`
- [ ] Backup Caddy certificates: See DOCKER.md
- [ ] Review logs weekly: `docker compose logs --since 168h`

## Troubleshooting

If deployment fails:

1. **Check DNS:**
```bash
nslookup responses.chutes.ai
# Should return your server IP
```

2. **Check ports:**
```bash
ss -tulpn | grep -E ':80|:443|:8282'
# Should show Docker processes
```

3. **Check containers:**
```bash
docker compose ps
docker compose logs
```

4. **Check Caddy certificates:**
```bash
docker compose exec caddy caddy list-certificates
```

5. **Test direct proxy:**
```bash
curl http://localhost:8282/health
# Should return {"status":"healthy"}
```

## Rollback

If needed to rollback:

```bash
# Stop current stack
docker compose down

# Restore previous version
git checkout <previous-commit>
./deploy.sh
```

## Success Criteria

✅ Both containers running
✅ Health endpoint returns 200 OK
✅ HTTPS accessible from internet
✅ Valid Let's Encrypt certificate
✅ Test request returns streaming response
✅ Logs show successful requests
