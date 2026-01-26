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

# Install Python packages for API
echo "Installing Python packages..."
pip3 install --quiet fastapi uvicorn[standard] pydantic python-dotenv streamlit pandas plotly 2>/dev/null || echo "Some packages already installed"

# Set DISPLAY for Wine apps
export DISPLAY=:0

# Start FastAPI Bridge in background
echo "Starting MT5 API Bridge on port 8001..."
cd /app/mt5_api_bridge
nohup python3 main.py > /tmp/api.log 2>&1 &

# Wait a bit for API to start
sleep 3

# Start Streamlit Dashboard in background
echo "Starting Streamlit Dashboard on port 8501..."
cd /app/streamlit_project
export MT5_API_URL="http://localhost:8001"
export USE_REMOTE_API="false"
nohup streamlit run app.py --server.port=8501 --server.address=0.0.0.0 > /tmp/dashboard.log 2>&1 &

echo "==================================="
echo "✅ All services started!"
echo "   - VNC: http://localhost:3000"
echo "   - API: http://localhost:8001"
echo "   - Dashboard: http://localhost:8501"
echo "==================================="

# Keep container running and show logs
echo "Tailing logs (Ctrl+C to stop)..."
tail -f /tmp/api.log /tmp/dashboard.log
