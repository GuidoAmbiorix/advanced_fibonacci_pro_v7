#!/bin/bash
# Quick test script to verify EA-Tester can access and run your EA

set -e

echo "=== Testing EA-Tester Integration ==="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if EA files exist
echo -n "1. Checking EA files... "
if [ -f "./portafolio_manager/Portfolio_Governor.ex5" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} Portfolio_Governor.ex5 not found!"
    exit 1
fi

# Check if hooks directory exists
echo -n "2. Checking hooks directory... "
if [ -f "./dashboard/ea_tester_hooks/prepare_ea.sh" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} prepare_ea.sh not found!"
    exit 1
fi

# Pull EA-Tester image
echo -n "3. Pulling EA-Tester image... "
if docker pull ea31337/ea-tester:latest &> /dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} Failed to pull image!"
    exit 1
fi

# Test EA-Tester help command
echo -n "4. Testing EA-Tester help... "
if docker run --rm ea31337/ea-tester:latest help &> /dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} EA-Tester help command failed!"
    exit 1
fi

# Test mounting volumes
echo -n "5. Testing volume mounts... "
TEST_OUTPUT=$(docker run --rm \
    -v "$(pwd)/portafolio_manager:/opt/ea:ro" \
    ea31337/ea-tester:latest \
    bash -c "ls -la /opt/ea/*.ex5 2>&1")

if echo "$TEST_OUTPUT" | grep -q "Portfolio_Governor.ex5"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "Volume mount test failed. Output:"
    echo "$TEST_OUTPUT"
    exit 1
fi

echo ""
echo -e "${GREEN}=== All tests passed! ===${NC}"
echo ""
echo "Your EA-Tester integration is ready."
echo "Next steps:"
echo "  1. Rebuild dashboard: docker-compose build dashboard"
echo "  2. Restart services: docker-compose --profile app up -d"
echo "  3. Access dashboard: http://localhost:8501"
echo "  4. Start optimization and check logs"
