#!/bin/bash
# Simplified startup: Only Dashboard + MT5, no API needed

echo "==================================="
echo "Starting MT5 Trading System..."
echo "==================================="

# Start MT5 VNC service (s6-overlay) in background
# We capture its PID to wait for it later
/init &
INIT_PID=$!

# Wait for Wine/MT5 to initialize
echo "Waiting for Wine/MT5 to initialize..."
sleep 15

# ============================================
# Phase 1 & 2: Manual Wheel Injection
# (Bypasses Wine pip/installer issues)
# ============================================
echo "========================================="
echo "Injecting Windows Python packages..."
echo "========================================="

SITE_PACKAGES="/config/.wine/drive_c/Program Files (x86)/Python39-32/Lib/site-packages"
WHEEL_DIR="/tmp/win_wheels"

# Verify Wine Python directory exists
if [ ! -d "$SITE_PACKAGES" ]; then
    echo "⚠️  Wine Python site-packages not found at $SITE_PACKAGES"
    echo "    Attempting to find it..."
    SITE_PACKAGES=$(find /config/.wine -name "site-packages" -type d | grep "Python39" | head -1)
    echo "    Found: $SITE_PACKAGES"
fi

if [ -d "$SITE_PACKAGES" ]; then
    echo "Downloading Windows wheels using Linux pip..."
    mkdir -p "$WHEEL_DIR"
    
    # Download Windows 32-bit wheels for Python 3.9
    # CRITICAL: Force numpy<2 because MetaTrader5 package is not compatible with numpy 2.x yet
    # This downloads rpyc, MetaTrader5, and their dependencies (plumbum, numpy, etc.)
    python3 -m pip download \
        --dest "$WHEEL_DIR" \
        --platform win32 \
        --python-version 3.9 \
        --implementation cp \
        --abi cp39 \
        --only-binary=:all: \
        --quiet \
        rpyc MetaTrader5 python-dateutil "numpy<2"
        
    if [ $? -eq 0 ]; then
        echo "✅ Wheels downloaded successfully"
        
        # Extract wheels directly to site-packages
        # This simulates 'pip install' without running code in Wine
        echo "Extracting wheels to $SITE_PACKAGES..."
        for whl in "$WHEEL_DIR"/*.whl; do
            filename=$(basename "$whl")
            echo "   Installing $filename..."
            python3 -m zipfile -e "$whl" "$SITE_PACKAGES"
        done
        echo "✅ Packages injected successfully"
    else
        echo "❌ Failed to download wheels"
    fi
    
    # Clean up
    rm -rf "$WHEEL_DIR"
else
    echo "❌ Could not find Wine Python site-packages directory"
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

# Trap signals for graceful shutdown
trap "kill $INIT_PID $MT5LINUX_PID $DASH_PID; exit" SIGINT SIGTERM

# Monitor processes
# We tail the log for visibility, but allow the script to wait indefinitely
tail -f /tmp/dashboard.log &
wait $INIT_PID
