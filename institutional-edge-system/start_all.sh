#!/bin/bash
# ============================================================================
# INSTITUTIONAL EDGE PRO - Unified Startup Script
# ============================================================================
# Complete infrastructure: 14 services in one docker-compose.yml
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

# 1. Create Directories
echo -e "${BLUE}[1/4] Creating directories...${NC}"
mkdir -p nginx/logs
mkdir -p logs
mkdir -p backend/logs
mkdir -p monitoring

# 2. Check Docker
echo -e "${BLUE}[2/4] Checking Docker status...${NC}"
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Docker is running${NC}"

# 3. Start All Services
echo -e "${BLUE}[3/4] Starting all 14 services...${NC}"

docker compose up -d --build
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to start services.${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ All services started${NC}"

# 4. Wait for Health
echo -e "${BLUE}[4/4] Waiting for services to initialize...${NC}"
sleep 15

# Check service health
echo ""
echo "Checking service health..."
echo "-----------------------------------------"

# PostgreSQL
if docker exec trading_postgres pg_isready -U trading > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ PostgreSQL is healthy${NC}"
else
    echo -e "${YELLOW}  ⚠ PostgreSQL not ready yet${NC}"
fi

# Redis
if docker exec trading_redis redis-cli ping > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Redis is healthy${NC}"
else
    echo -e "${YELLOW}  ⚠ Redis not responding${NC}"
fi

# RabbitMQ
if curl -s http://localhost:15672 > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ RabbitMQ is healthy${NC}"
else
    echo -e "${YELLOW}  ⚠ RabbitMQ not responding yet${NC}"
fi

# Backend API
if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Backend API is healthy${NC}"
else
    echo -e "${YELLOW}  ⚠ Backend not responding yet (may still be starting)${NC}"
fi

# Nginx
if curl -s http://localhost/health > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Nginx proxy is healthy${NC}"
else
    echo -e "${YELLOW}  ⚠ Nginx not responding yet${NC}"
fi

# Prometheus
if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Prometheus is healthy${NC}"
else
    echo -e "${YELLOW}  ⚠ Prometheus not responding yet${NC}"
fi

# Grafana
if curl -s http://localhost:3002/api/health > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Grafana is healthy${NC}"
else
    echo -e "${YELLOW}  ⚠ Grafana not responding yet${NC}"
fi

echo ""
echo "========================================="
echo -e "${GREEN}SYSTEM READY 🚀${NC}"
echo "========================================="
echo ""
echo "Access URLs:"
echo "-----------------------------------------"
echo "Frontend:        http://localhost/"
echo "Backend API:     http://localhost/api/"
echo "MT5 VNC:         http://localhost:3000/"
echo ""
echo "Monitoring:"
echo "-----------------------------------------"
echo "Grafana:         http://localhost:3002/ (admin/admin)"
echo "Prometheus:      http://localhost:9090/"
echo "RabbitMQ UI:     http://localhost:15672/ (guest/guest)"
echo "PGAdmin:         http://localhost:5050/ (admin@trading.com/admin)"
echo ""
echo "To view logs:"
echo "  docker compose logs -f backend"
echo "  docker compose logs -f postgres"
echo ""
echo "To stop everything:"
echo "  docker compose down"
echo ""
