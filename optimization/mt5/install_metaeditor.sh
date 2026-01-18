#!/bin/bash
# Install MetaEditor if not present

METAEDITOR_PATH="/config/.wine/drive_c/Program Files/MetaTrader 5/metaeditor64.exe"

if [ -f "$METAEDITOR_PATH" ]; then
    echo "MetaEditor already installed"
    exit 0
fi

echo "MetaEditor not found. Installing..."

# MetaEditor comes with the full MT5 package - need to reinstall with full components
# Or download MetaEditor separately from MetaQuotes

cd /tmp

# Download the latest MT5 setup
wget -q https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe -O mt5setup.exe

if [ ! -f mt5setup.exe ]; then
    echo "Failed to download MT5 installer"
    exit 1
fi

# Run the installer with full installation (this should include MetaEditor)
# We need to run it in the existing Wine prefix
export WINEPREFIX="/config/.wine"
export DISPLAY=:0

echo "Running MT5 installer (this may take a few minutes)..."
wine mt5setup.exe /auto

# Wait for installation to complete
sleep 30

# Check if MetaEditor was installed
if [ -f "$METAEDITOR_PATH" ]; then
    echo "✅ MetaEditor installed successfully"
else
    echo "⚠️ MetaEditor still not found. Manual installation may be required."
fi

rm -f mt5setup.exe
