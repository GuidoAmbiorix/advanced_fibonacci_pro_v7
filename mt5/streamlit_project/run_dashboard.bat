@echo off
TITLE Elite MT5 Trading Intelligence Platform
color 0A

REM Navigate to project directory
cd /d "%~dp0"

echo.
echo ====================================================================
echo       Elite MT5 Trading Intelligence Platform - Launcher
echo ====================================================================
echo.
echo [%date% %time%] Starting initialization...
echo.

REM ============================================================
REM Step 1: Check Python Installation
REM ============================================================
echo [1/6] Checking Python installation...
python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    color 0C
    echo.
    echo ❌ ERROR: Python is not installed or not in PATH
    echo.
    echo Please install Python 3.8+ from: https://www.python.org/downloads/
    echo Make sure to check "Add Python to PATH" during installation
    echo.
    pause
    exit /b 1
)
python --version
echo    ✓ Python found
echo.

REM ============================================================
REM Step 2: Check and Create Configuration
REM ============================================================
echo [2/6] Checking configuration...
if not exist ".env" (
    echo    ⚠ .env file not found
    if exist ".env.example" (
        echo    → Creating .env from .env.example...
        copy ".env.example" ".env" >nul
        echo    ✓ .env file created
        echo.
        echo    ⚠ IMPORTANT: Please edit .env and update MT5_SETS_PATH
        echo    Default path: C:\Users\gamparo\Desktop\Projects\advanced_fibonacci_pro_v7\mt5\portafolio_manager\sets
        echo.
    ) else (
        color 0E
        echo    ⚠ WARNING: .env.example not found
        echo    → Application will use default configuration
        echo.
    )
) else (
    echo    ✓ .env file found
)
echo.

REM ============================================================
REM Step 3: Create Required Directories
REM ============================================================
echo [3/6] Creating required directories...
if not exist "logs" (
    mkdir "logs"
    echo    → Created logs directory
)
if not exist "data" (
    mkdir "data"
    echo    → Created data directory
)
echo    ✓ Directories ready
echo.

REM ============================================================
REM Step 4: Check/Install Dependencies
REM ============================================================
echo [4/6] Checking dependencies...
pip show streamlit >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo    ⚠ Dependencies not installed
    echo    → Installing required packages...
    echo.
    pip install -r requirements.txt
    if %ERRORLEVEL% NEQ 0 (
        color 0C
        echo.
        echo ❌ ERROR: Failed to install dependencies
        echo.
        echo Please manually run: pip install -r requirements.txt
        echo.
        pause
        exit /b 1
    )
    echo    ✓ Dependencies installed
) else (
    echo    ✓ Dependencies already installed
)
echo.

REM ============================================================
REM Step 5: Check MT5 Terminal
REM ============================================================
echo [5/6] Checking MetaTrader 5...
tasklist /FI "IMAGENAME eq terminal64.exe" 2>NUL | find /I /N "terminal64.exe">NUL
if %ERRORLEVEL% EQU 0 (
    echo    ✓ MT5 Terminal is running
) else (
    color 0E
    echo    ⚠ WARNING: MT5 Terminal (terminal64.exe) not detected
    echo    → Please ensure MT5 is running before connecting
)
echo.

REM ============================================================
REM Step 6: Launch Application
REM ============================================================
echo [6/6] Launching application...
echo.
echo ====================================================================
echo    Application starting on http://localhost:8501
echo ====================================================================
echo.
echo    • Configuration: .env
echo    • Logs: logs/mt5_platform.log
echo    • Errors: logs/mt5_platform_errors.log
echo.
echo    Press Ctrl+C to stop the application
echo.
echo ====================================================================
echo.

REM Launch Streamlit
python -m streamlit run app.py

REM Check if Streamlit failed
if %ERRORLEVEL% NEQ 0 (
    color 0C
    echo.
    echo ====================================================================
    echo ❌ Application failed to start
    echo ====================================================================
    echo.
    echo Troubleshooting steps:
    echo 1. Check logs/mt5_platform_errors.log for details
    echo 2. Verify .env configuration (especially MT5_SETS_PATH)
    echo 3. Ensure MT5 Terminal is running
    echo 4. Try reinstalling dependencies: pip install -r requirements.txt
    echo.
    echo For detailed help, see UPGRADE_GUIDE.md
    echo.
    pause
    exit /b 1
)

REM Normal exit
echo.
echo ====================================================================
echo Application closed normally
echo ====================================================================
pause
