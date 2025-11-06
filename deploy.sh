#!/bin/bash
# OpenAI Responses Proxy - Management Script

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  OpenAI Responses Proxy - Management    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo

echo -e "${YELLOW}Choose action:${NC}"
echo "1) Deploy"
echo "2) Stop"
read -p "Enter choice (1/2): " choice

case "${choice}" in
    1)
        # Check if .env exists
        if [ ! -f .env ]; then
            echo -e "${YELLOW}⚠️  .env file not found${NC}"
            echo -e "${BLUE}Creating .env from .env.sample...${NC}"
            cp .env.sample .env
            echo -e "${GREEN}✓ Created .env${NC}"
            echo -e "${YELLOW}⚠️  Please edit .env with your settings, then run this script again.${NC}"
            exit 0
        fi

        # Load environment
        source .env

        echo -e "${BLUE}Configuration:${NC}"
        echo "  Backend: $BACKEND_URL"
        echo "  Proxy Port: $HOST_PORT"
        echo "  Caddy Domain: $CADDY_DOMAIN"
        echo "  Caddy Port: $CADDY_PORT"
        echo "  TLS: $CADDY_TLS"
        echo

        # Check if Docker is running
        if ! docker info > /dev/null 2>&1; then
            echo -e "${RED}❌ Docker is not running${NC}"
            exit 1
        fi

        # Build and deploy
        echo -e "${BLUE}Building containers...${NC}"
        docker compose build

        echo -e "${BLUE}Starting services...${NC}"
        docker compose up -d

        echo -e "${BLUE}Waiting for services to be ready...${NC}"
        sleep 3

        # Check health
        echo -e "${BLUE}Checking health...${NC}"
        if curl -s -f http://localhost:$HOST_PORT/health > /dev/null; then
            echo -e "${GREEN}✓ Proxy is healthy${NC}"
        else
            echo -e "${RED}❌ Proxy health check failed${NC}"
            echo -e "${YELLOW}Check logs: docker compose logs -f${NC}"
            exit 1
        fi

        # Show status
        echo
        echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  Deployment Complete!                    ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
        echo
        echo -e "${BLUE}Services:${NC}"
        docker compose ps

        echo
        echo -e "${BLUE}Access URLs:${NC}"
        if [ "$CADDY_TLS" = "true" ]; then
            echo "  https://$CADDY_DOMAIN/v1/responses"
            echo "  https://$CADDY_DOMAIN/health"
        else
            echo "  http://$CADDY_DOMAIN:$CADDY_PORT/v1/responses"
            echo "  http://$CADDY_DOMAIN:$CADDY_PORT/health"
        fi
        echo "  http://localhost:$HOST_PORT/v1/responses (direct)"
        echo "  http://localhost:$HOST_PORT/health (direct)"

        echo
        echo -e "${BLUE}Useful commands:${NC}"
        echo "  docker compose logs -f                 # View logs"
        echo "  docker compose logs -f openai-responses-proxy  # Proxy logs only"
        echo "  docker compose logs -f caddy           # Caddy logs only"
        echo "  docker compose restart                 # Restart all"
        echo "  docker compose down                    # Stop all"
        echo

        if [ "$CADDY_TLS" = "true" ]; then
            echo -e "${YELLOW}Note: TLS certificate acquisition may take a few moments.${NC}"
            echo -e "${YELLOW}Ensure DNS for $CADDY_DOMAIN points to this server.${NC}"
        fi
        ;;
    2)
        echo "🛑 Stopping OpenAI Responses Proxy..."
        docker compose down

        echo "✅ All services stopped"
        echo
        echo "To remove volumes (certificates, etc.):"
        echo "  docker compose down -v"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

