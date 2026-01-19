@echo off
TITLE Quantum Trading Dashboard
echo ===================================================
echo 🚀 Starting Quantum Trading Dashboard
echo ===================================================

echo.
echo 📦 Checking Dependencies...
pip install -r requirements.txt
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Failed to install dependencies!
    pause
    exit /b
)

echo.
echo 🧹 Cleaning previous session data...
:: Optional: Remove-Item "data\optimization.db" -Force

echo.
echo 🌐 Launching Streamlit...
python -m streamlit run dashboard.py --server.port 8501 --server.address localhost

pause
