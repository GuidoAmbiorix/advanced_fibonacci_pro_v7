#!/bin/bash
# Startup script to run MT5, API, and Dashboard inside Wine container

echo "==================================="
echo "Starting MT5 Trading System..."
echo "==================================="

# Start the original MT5 VNC service in background
/init &

# Wait for MT5 to be ready
echo "Waiting for Wine/MT5 to initialize..."
sleep 15

# Install system packages
echo "Installing system packages..."
apt-get update -qq
apt-get install -y python3-pip python3-dev build-essential -qq

# Upgrade pip
echo "Upgrading pip..."
python3 -m pip install --upgrade pip --break-system-packages --quiet

# Install Python packages
echo "Installing Python packages (this may take a minute)..."
python3 -m pip install --break-system-packages --quiet \
    fastapi==0.109.0 \
    uvicorn[standard]==0.27.0 \
    pydantic==2.5.0 \
    python-dotenv==1.0.0 \
    streamlit==1.31.0 \
    pandas==2.1.4 \
    plotly==5.18.0 \
    sqlalchemy==2.0.25

echo "✅ Packages installed"

# Set DISPLAY for Wine apps
export DISPLAY=:0

# Start FastAPI Bridge in background
echo "Starting MT5 API Bridge on port 8001..."
cd /app/mt5_api_bridge
nohup python3 main.py > /tmp/api.log 2>&1 &
API_PID=$!

# Wait a bit for API to start
sleep 5

# Check if API started
if ps -p $API_PID > /dev/null; then
    echo "✅ API started (PID: $API_PID)"
else
    echo "❌ API failed to start. Check /tmp/api.log"
    cat /tmp/api.log
fi

# Start Streamlit Dashboard in background
echo "Starting Streamlit Dashboard on port 8501..."
cd /app/streamlit_project

# Set environment variables
export MT5_API_URL="http://localhost:8001"
export USE_REMOTE_API="false"

nohup python3 -m streamlit run app.py \
    --server.port=8501 \
    --server.address=0.0.0.0 \
    --server.headless=true \
    > /tmp/dashboard.log 2>&1 &
DASH_PID=$!

# Wait a bit
sleep 5

# Check if Dashboard started
if ps -p $DASH_PID > /dev/null; then
    echo "✅ Dashboard started (PID: $DASH_PID)"
else
    echo "❌ Dashboard failed to start. Check /tmp/dashboard.log"
    cat /tmp/dashboard.log
fi

echo "==================================="
echo "✅ All services started!"
echo "   - VNC: http://localhost:3000"
echo "   - API: http://localhost:8001"
echo "   - Dashboard: http://localhost:8501"
echo "==================================="
echo ""
echo "Checking service status..."
echo ""

# Check ports
netstat -tuln | grep -E '3000|8001|8501' || echo "Waiting for ports to bind..."

echo ""
echo "==================================="
echo "Tailing logs (Ctrl+C to stop)..."
echo "==================================="

# Keep container running and show logs
tail -f /tmp/api.log /tmp/dashboard.log
