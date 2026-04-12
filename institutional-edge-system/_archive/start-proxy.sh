#!/bin/bash

# ============================================================================
# INSTITUTIONAL EDGE PRO - Proxy Startup Script
# ============================================================================

set -e

echo "========================================="
echo "Institutional Edge Pro - Proxy Setup"
echo "========================================="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create nginx logs directory
echo -e "${BLUE}Creating nginx logs directory...${NC}"
mkdir -p nginx/logs

# Check if docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${YELLOW}Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker is running${NC}"

# Start nginx proxy
echo -e "${BLUE}Starting nginx reverse proxy...${NC}"
docker-compose -f docker-compose.proxy.yml up -d

# Wait for nginx to start
echo -e "${BLUE}Waiting for nginx to start...${NC}"
sleep 3

# Check nginx health
if curl -s http://localhost/health > /dev/null; then
    echo -e "${GREEN}✓ Nginx proxy is running${NC}"
    echo ""
    echo "========================================="
    echo "Proxy URLs:"
    echo "========================================="
    echo -e "Health Check:    ${GREEN}http://localhost/health${NC}"
    echo -e "Orchestrator:    ${GREEN}http://localhost/${NC}"
    echo -e "Orchestrator API: ${GREEN}http://localhost/api/orchestrator${NC}"
    echo ""
    echo "Instance URLs (when instances are running):"
    echo -e "Instance 1:      ${GREEN}http://localhost/instance/1${NC}"
    echo -e "Instance 2:      ${GREEN}http://localhost/instance/2${NC}"
    echo -e "Instance N:      ${GREEN}http://localhost/instance/N${NC}"
    echo ""
    echo "========================================="
    echo -e "${GREEN}Setup complete!${NC}"
    echo "========================================="
    echo ""
    echo "Next steps:"
    echo "1. Create instances using the orchestrator"
    echo "2. Access instances through the proxy URLs above"
    echo ""
    echo "To view logs:"
    echo "  docker logs -f institutional_nginx_proxy"
    echo ""
    echo "To stop the proxy:"
    echo "  docker-compose -f docker-compose.proxy.yml down"
else
    echo -e "${YELLOW}⚠ Nginx proxy started but health check failed${NC}"
    echo "Checking logs..."
    docker logs institutional_nginx_proxy --tail 20
    exit 1
fi
