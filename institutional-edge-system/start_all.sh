#!/bin/bash
# ============================================================================
# INSTITUTIONAL EDGE PRO - Unified Startup Script
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "========================================="
echo "Institutional Edge Pro - System Startup"
echo "========================================="
echo ""

# 1. Create Log Directories
echo -e "${BLUE}[1/5] Creating log directories...${NC}"
mkdir -p nginx/logs
mkdir -p logs

# 2. Check Docker
echo -e "${BLUE}[2/5] Checking Docker status...${NC}"
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Docker is running${NC}"

# 3. Network Setup
echo -e "${BLUE}[3/5] Configuring network...${NC}"

# Check if bot-net network exists, if not create it
if ! docker network inspect bot-net > /dev/null 2>&1; then
    echo "  - Creating shared network 'bot-net'..."
    docker network create bot-net
else
    echo "  - Shared network 'bot-net' already exists."
fi

# Check if trading_network exists, if not create it
if ! docker network inspect trading_network > /dev/null 2>&1; then
    echo "  - Creating shared network 'trading_network'..."
    docker network create trading_network
else
    echo "  - Shared network 'trading_network' already exists."
fi

# 4. Start Services
echo -e "${BLUE}[4/5] Starting Services...${NC}"

echo "  - Starting Proxy Service..."
docker-compose -f docker-compose.proxy.yml up -d
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to start Proxy.${NC}"
    exit 1
fi

echo "  - Starting Shared Infrastructure (RabbitMQ)..."
docker-compose -f docker-compose.shared.yml up -d
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to start Shared Infrastructure.${NC}"
    exit 1
fi

echo "  - Starting Fleet Commander..."
docker-compose -f docker-compose.admin.yml up -d
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to start Orchestrator.${NC}"
    exit 1
fi

# 5. Wait for Health
echo -e "${BLUE}[5/5] Waiting for services to initialize...${NC}"
sleep 5

# Check Nginx Health
if curl -s http://localhost/health > /dev/null 2>&1; then
    echo -e "${GREEN}[OK] Proxy is Healthy${NC}"
else
    echo -e "${YELLOW}[WARNING] Proxy health check failed. Please check logs.${NC}"
fi

echo ""
echo "========================================="
echo -e "${GREEN}SYSTEM READY 🚀${NC}"
echo "========================================="
echo ""
echo "Access URLs:"
echo "-----------------------------------------"
echo "Fleet Commander: http://localhost:9000/"
echo "RabbitMQ:        http://localhost:15672/ (guest/guest)"
echo ""
echo "Instance URLs (Once Deployed):"
echo "-----------------------------------------"
echo "Instance 1:     http://localhost:81/ (Dashboard) - VNC: 3001"
echo "Instance 2:     http://localhost:82/ (Dashboard) - VNC: 3002"
echo ""
echo "NOTE: Each instance has its own dedicated MT5 terminal."
echo "      Access VNC ports (3001+) to login to broker accounts."
echo ""
echo "To Stop Everything:"
echo "  docker-compose -f docker-compose.admin.yml down"
echo "  docker-compose -f docker-compose.proxy.yml down"
echo "  docker-compose -f docker-compose.shared.yml down"
echo ""
