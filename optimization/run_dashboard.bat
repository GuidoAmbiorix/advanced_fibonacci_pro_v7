@echo off
cd /d "%~dp0"

echo ===================================================
echo 🛡️  OPTIMA: Institutional AI Optimization Dashboard
echo ===================================================

echo.
echo 📦 Checking Python...
python --version > nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Python is not installed or not in PATH.
    echo Please install Python 3.10+ and Add to PATH.
    pause
    exit /b
)

echo.
echo 📦 Checking/Installing Dependencies...
pip install -r requirements.txt
if %ERRORLEVEL% NEQ 0 (
    echo ⚠️ pip install failed. Ensure internet connection.
    pause
    exit /b
) else (
    echo ✅ Dependencies ready.
)

echo.
echo 🚀 Launching Dashboard...
echo    (Press Ctrl+C to stop)
echo.

:: Use python -m streamlit to avoid PATH issues
python -m streamlit run dashboard.py

pause
