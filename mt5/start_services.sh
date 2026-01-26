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

# ============================================
# Phase 1: Fix Wine Python pip
# ============================================
echo "========================================="
echo "Setting up Wine Python environment..."
echo "========================================="

# Download get-pip.py if not exists
if [ ! -f /tmp/get-pip.py ]; then
    echo "Downloading get-pip.py..."
    wget -q https://bootstrap.pypa.io/pip/3.9/get-pip.py -O /tmp/get-pip.py
    if [ $? -eq 0 ]; then
        echo "✅ get-pip.py downloaded"
    else
        echo "⚠️  Failed to download get-pip.py, trying alternative..."
        curl -s https://bootstrap.pypa.io/pip/3.9/get-pip.py -o /tmp/get-pip.py
    fi
fi

# Install pip in Wine Python
echo "Installing pip in Wine Python..."
wine "C:\Program Files (x86)\Python39-32\python.exe" /tmp/get-pip.py --quiet 2>/dev/null || \
    wine "C:\Program Files (x86)\Python39-32\python.exe" -m ensurepip --upgrade 2>/dev/null

# Verify pip installation
if wine "C:\Program Files (x86)\Python39-32\Scripts\pip.exe" --version >/dev/null 2>&1; then
    echo "✅ Wine Python pip installed"
else
    echo "⚠️  Wine Python pip installation had issues"
fi

# ============================================
# Phase 2: Install Required Packages in Wine
# ============================================
echo "Installing required packages in Wine Python..."

# Install rpyc
wine "C:\Program Files (x86)\Python39-32\Scripts\pip.exe" install --quiet rpyc 2>/dev/null && \
    echo "✅ rpyc installed" || echo "⚠️  rpyc installation had issues"

# Install MetaTrader5
wine "C:\Program Files (x86)\Python39-32\Scripts\pip.exe" install --quiet --upgrade MetaTrader5 2>/dev/null && \
    echo "✅ MetaTrader5 installed" || echo "⚠️  MetaTrader5 installation had issues"

# Install python-dateutil
wine "C:\Program Files (x86)\Python39-32\Scripts\pip.exe" install --quiet python-dateutil 2>/dev/null && \
    echo "✅ python-dateutil installed" || echo "⚠️  python-dateutil installation had issues"

# ============================================
# Phase 3: Install Linux Python Packages
# ============================================
# Install Python packages from requirements.txt
echo "Installing Python packages from requirements.txt..."
if [ -f /app/streamlit_project/requirements.txt ]; then
    python3 -m pip install --break-system-packages --quiet -r /app/streamlit_project/requirements.txt 2>/dev/null || \
    python3 -m pip install --break-system-packages -r /app/streamlit_project/requirements.txt
    echo "✅ Packages installed"
else
    echo "⚠️  requirements.txt not found, installing minimal packages..."
    python3 -m pip install --break-system-packages --quiet streamlit pandas plotly sqlalchemy python-dotenv
    echo "✅ Minimal packages installed"
fi

# Configure PYTHONPATH to include abc user's packages (where mt5linux is installed)
echo "Configuring Python path for mt5linux access..."
export PYTHONPATH="/config/.local/lib/python3.11/site-packages:$PYTHONPATH"
echo "✅ PYTHONPATH configured"

# Set environment for Wine
export DISPLAY=:0

# ============================================
# Phase 4: Start mt5linux RPyC Server
# ============================================
echo "Starting mt5linux RPyC server on port 18812..."

# Start server in background
nohup python3 -m mt5linux \
    "C:\Program Files (x86)\Python39-32\python.exe" \
    --host 0.0.0.0 \
    --port 18812 \
    > /tmp/mt5linux_server.log 2>&1 &

MT5LINUX_PID=$!
sleep 3

# Verify server started
if ps -p $MT5LINUX_PID > /dev/null 2>&1; then
    echo "✅ mt5linux server started (PID: $MT5LINUX_PID)"
else
    echo "⚠️  mt5linux server may have issues. Check /tmp/mt5linux_server.log"
fi

# ============================================
# Phase 5: Start Streamlit Dashboard
# ============================================
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
