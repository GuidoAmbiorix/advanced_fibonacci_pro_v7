#!/bin/bash
set -e

# Set environment
export DISPLAY=:0
export WINEPREFIX=/home/mt5/.wine
export WINEARCH=win32

# Start X virtual framebuffer
echo "Starting Xvfb..."
Xvfb :0 -screen 0 1024x768x16 &
sleep 2

# Start Window Manager
echo "Starting Fluxbox..."
fluxbox &
sleep 2

# Start VNC Server
echo "Starting X11VNC..."
x11vnc -display :0 -forever -usepw -rfbport 5900 -bg &
sleep 2

# Check if MT5 is already installed
if [ ! -f "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal.exe" ]; then
    echo "MT5 not found. Waiting for manual installation via VNC..."
    # Optional: Download MT5 installer automatically if you want
    # wget https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe -O /home/mt5/mt5setup.exe
    # wine /home/mt5/mt5setup.exe &
else
    echo "Starting MT5 Terminal..."
    wine "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal.exe" /portable &
fi

# Keep container alive
tail -f /dev/null
