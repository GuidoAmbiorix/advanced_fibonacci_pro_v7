#!/bin/bash
# Entrypoint script for MT5 Docker container

echo "=========================================="
echo "  MT5 Docker Container Starting..."
echo "=========================================="

# Start Xvfb in background
echo "🖥️ Starting Xvfb virtual display..."
Xvfb :99 -screen 0 1920x1080x24 &
export DISPLAY=:99
sleep 2

# Verify Wine and MT5
echo "🍷 Checking Wine..."
wine --version || echo "Wine not found!"

echo "📊 Checking MT5..."
if [ -f "/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe" ]; then
    echo "✅ MT5 is installed"
else
    echo "⚠️ MT5 not found, attempting install..."
    wget -q -O /tmp/mt5setup.exe "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
    xvfb-run -a wine /tmp/mt5setup.exe /auto
    sleep 30
    rm -f /tmp/mt5setup.exe
fi

# Start supervisor (manages RPyC server)
echo "🚀 Starting Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
