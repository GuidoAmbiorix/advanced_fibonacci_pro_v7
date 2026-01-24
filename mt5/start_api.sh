#!/bin/bash
# Script to install Python and start MT5 API server inside MT5 container
# Run this with: docker exec -it trading_mt5 /app/start_api.sh

echo "Installing Python and dependencies..."
apt-get update
apt-get install -y python3 python3-pip python3-dev

echo "Installing Python packages..."
cd /app
pip3 install --no-cache-dir -r requirements.txt

echo "Starting MT5 API Server on port 8001..."
python3 mt5_api_server.py
