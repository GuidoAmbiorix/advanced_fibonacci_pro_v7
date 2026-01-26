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

WINE_PYTHON="C:\Program Files (x86)\Python39-32\python.exe"
WINE_PIP="C:\Program Files (x86)\Python39-32\Scripts\pip.exe"

# Method 1: Try ensurepip first (fastest if available)
echo "Trying ensurepip..."
if wine "$WINE_PYTHON" -m ensurepip --upgrade 2>/dev/null; then
    echo "✅ pip installed via ensurepip"
else
    echo "⚠️  ensurepip not available, using get-pip.py..."
    
    # Method 2: Download and run get-pip.py
    # Remove old corrupted file
    rm -f /tmp/get-pip.py
    
    # Download with correct URL
    echo "Downloading get-pip.py from bootstrap.pypa.io..."
    wget --no-check-certificate -q https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py 2>/dev/null || \
        curl -k -s https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
    
    # Verify download (should be ~2MB, not 153 bytes!)
    if [ -f /tmp/get-pip.py ] && [ $(stat -c%s /tmp/get-pip.py) -gt 100000 ]; then
        echo "✅ get-pip.py downloaded ($(stat -c%s /tmp/get-pip.py) bytes)"
        
        # Run get-pip.py
        wine "$WINE_PYTHON" /tmp/get-pip.py --no-warn-script-location 2>/dev/null && \
            echo "✅ pip installed via get-pip.py" || \
            echo "⚠️  get-pip.py installation had issues"
    else
        echo "❌ Failed to download get-pip.py"
    fi
fi

# Verify final pip installation
if wine "$WINE_PIP" --version >/dev/null 2>&1; then
    echo "✅ Wine Python pip is working"
    wine "$WINE_PIP" --version 2>/dev/null | head -1
else
    echo "❌ Wine Python pip not available - will skip package installation"
fi

# ============================================
# Phase 2: Install Required Packages in Wine
# ============================================

# Only proceed if pip is available
if wine "$WINE_PIP" --version >/dev/null 2>&1; then
    echo "Installing required packages in Wine Python..."
    
    # Install rpyc
    wine "$WINE_PIP" install --quiet --no-warn-script-location rpyc 2>/dev/null && \
        echo "✅ rpyc installed" || echo "⚠️  rpyc installation had issues"
    
    # Install MetaTrader5
    wine "$WINE_PIP" install --quiet --no-warn-script-location --upgrade MetaTrader5 2>/dev/null && \
        echo "✅ MetaTrader5 installed" || echo "⚠️  MetaTrader5 installation had issues"
    
    # Install python-dateutil
    wine "$WINE_PIP" install --quiet --no-warn-script-location python-dateutil 2>/dev/null && \
        echo "✅ python-dateutil installed" || echo "⚠️  python-dateutil installation had issues"
else
    echo "⚠️  Skipping Wine package installation (pip not available)"
fi

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
