#!/bin/bash
set -e

export DISPLAY=:0
export WINEPREFIX=/home/mt5/.wine
export WINEARCH=win64

# Start X virtual framebuffer
echo "Starting Xvfb..."
Xvfb :0 -screen 0 1280x1024x24 &
sleep 2

# Start Window Manager
echo "Starting Fluxbox..."
fluxbox &
sleep 2

# Start VNC Server
echo "Starting VNC on port 5900..."
x11vnc -display :0 -forever -usepw -rfbport 5900 -bg &
sleep 2

# Check if MT5 is installed
MT5_PATH="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
if [ -f "$MT5_PATH" ]; then
    echo "Starting MT5 Terminal..."
    wine "$MT5_PATH" /portable &
else
    echo "MT5 not found. Please install via VNC."
    echo "Download: https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
fi

# Keep alive
tail -f /dev/null
