#!/bin/bash
# ============================================================================
# INSTITUTIONAL EDGE PRO - Startup Script
# ============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================="
echo "  Institutional Edge Pro - Starting..."
echo "========================================="
echo ""

# Check Docker
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker is not running. Start Docker and try again.${NC}"
    exit 1
fi

# Create log directories
mkdir -p logs

# Build and start all services
echo -e "${BLUE}Starting all services...${NC}"
docker compose up -d --build

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  SYSTEM READY${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Access URLs:"
echo "  Dashboard:      http://localhost:80"
echo "  Backend API:    http://localhost:8000"
echo "  MT5 VNC:        http://localhost:3000  (password: trading)"
echo "  RabbitMQ UI:    http://localhost:15672  (guest/guest)"
echo ""
echo "To stop:  docker compose down"
echo "Logs:     docker compose logs -f"
echo ""
