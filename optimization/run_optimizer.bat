@echo off
setlocal enabledelayedexpansion

echo ========================================
echo   AI Trading Optimizer - Smart Launcher
echo ========================================
echo.

cd /d "%~dp0"

REM Check if Python is installed
echo [1/4] Checking Python installation...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ❌ ERROR: Python is not installed or not in PATH
    echo.
    echo 📋 To fix this:
    echo    1. Download Python from: https://www.python.org/downloads/
    echo    2. During installation, CHECK "Add Python to PATH"
    echo    3. Restart this script
    echo.
    pause
    exit /b 1
)

for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
echo    ✅ Python %PYTHON_VERSION% detected
echo.

REM Check if pip is available
echo [2/4] Checking pip availability...
python -m pip --version >nul 2>&1
if %errorlevel% neq 0 (
    echo    ⚠️  pip not found, attempting to install...
    python -m ensurepip --default-pip
    if %errorlevel% neq 0 (
        echo    ❌ Failed to install pip
        echo    Please install pip manually: https://pip.pypa.io/en/stable/installation/
        pause
        exit /b 1
    )
)
echo    ✅ pip is ready
echo.

REM Check if requirements.txt exists
echo [3/4] Installing dependencies...
if not exist requirements.txt (
    echo    ⚠️  requirements.txt not found, creating default...
    (
        echo optuna==3.5.0
        echo pandas==2.1.4
        echo numpy==1.26.3
        echo scikit-learn==1.4.0
        echo matplotlib==3.8.2
        echo plotly==5.18.0
        echo joblib==1.3.2
    ) > requirements.txt
)

REM Install with proper error handling
python -m pip install --upgrade pip --quiet
python -m pip install -r requirements.txt --quiet

if %errorlevel% neq 0 (
    echo.
    echo    ❌ Installation failed. Trying with verbose output...
    echo.
    python -m pip install -r requirements.txt
    if %errorlevel% neq 0 (
        echo.
        echo    ❌ Critical Error: Could not install dependencies
        echo    Please check your internet connection and try again
        pause
        exit /b 1
    )
)
echo    ✅ All dependencies installed
echo.

REM Check if optimizer.py exists
echo [4/4] Launching optimizer...
if not exist optimizer.py (
    echo    ❌ ERROR: optimizer.py not found in current directory
    echo    Current directory: %CD%
    echo.
    pause
    exit /b 1
)

echo    ✅ Starting Optuna Optimizer...
echo.
echo ========================================
echo.

python optimizer.py

if %errorlevel% neq 0 (
    echo.
    echo ⚠️  Optimizer exited with error code: %errorlevel%
)

echo.
echo ========================================
echo   Optimization Complete
echo ========================================
pause