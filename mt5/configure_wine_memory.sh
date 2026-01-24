#!/bin/bash
# Configure Wine to allocate 4GB RAM for MT5
# Run this inside the MT5 container after it starts

export WINEPREFIX=/config/.wine
export WINEARCH=win64

# Set Wine to 64-bit mode for better memory handling
wine64 reg add "HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\Memory Management" /v LargeAddressAware /t REG_DWORD /d 1 /f

# Increase virtual memory
wine64 reg add "HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\Memory Management" /v PagingFiles /t REG_SZ /d "c:\\pagefile.sys 4096 8192" /f

# Set MT5 terminal to use more memory
wine64 reg add "HKEY_CURRENT_USER\\Software\\Wine\\WineDbg" /v ShowCrashDialog /t REG_DWORD /d 0 /f

echo "Wine memory configuration complete"
