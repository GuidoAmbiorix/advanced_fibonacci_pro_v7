#!/bin/bash
export DISPLAY=:0
export WINEPREFIX="/home/mt5/.wine"

# Wait for X server to be ready
sleep 5

MT5_PATH="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"

if [ ! -f "$MT5_PATH" ]; then
    echo "MT5 not found. Downloading installer..."
    wget https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe -O /home/mt5/mt5setup.exe
    echo "Starting installer..."
    # Launch installer in background
    wine /home/mt5/mt5setup.exe &
    wait
else
    echo "Starting MT5..."
    wine "$MT5_PATH" /portable /login:123456 /password:secret &
    # Keep script running while Wine processes are alive
    while pgrep -f terminal64.exe > /dev/null; do sleep 5; done
fi
