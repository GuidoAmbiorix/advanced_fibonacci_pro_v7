#!/bin/bash
# Simplified startup: Only Dashboard + MT5, no API needed

echo "==================================="
echo "Starting MT5 Trading System..."
echo "==================================="

# Start MT5 VNC service in background
/init &

# Wait for Wine/MT5 to initialize
echo "Waiting for Wine/MT5 to initialize..."
sleep 15

# Install Python packages (silently, avoid noise)
echo "Installing Python packages..."
python3 -m pip install --break-system-packages --quiet \
    streamlit pandas plotly sqlalchemy 2>/dev/null || echo "Some packages already installed"

echo "✅ Setup complete"

# Set environment for Wine
export DISPLAY=:0

# Start Streamlit Dashboard
echo "Starting Streamlit Dashboard on port 8501..."
cd /app/streamlit_project

# Launch Streamlit
python3 -m streamlit run app.py \
    --server.port=8501 \
    --server.address=0.0.0.0 \
    --server.headless=true \
    > /tmp/dashboard.log 2>&1 &

DASH_PID=$!
sleep 5

# Check if started
if ps -p $DASH_PID > /dev/null 2>&1; then
    echo "✅ Dashboard started (PID: $DASH_PID)"
else
    echo "❌ Dashboard failed. Check logs:"
    tail -30 /tmp/dashboard.log
    exit 1
fi

echo "==================================="
echo "✅ System Ready!"
echo "   - Dashboard: http://localhost:8501"
echo "   - VNC: http://localhost:3000"
echo "==================================="

# Show listening ports
echo "Ports:"
ss -tuln 2>/dev/null | grep -E ':(3000|8501)' || echo "Checking..."

echo ""
echo "Tailing dashboard logs..."
tail -f /tmp/dashboard.log
