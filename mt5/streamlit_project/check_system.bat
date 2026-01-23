@echo off
TITLE MT5 Platform - System Check
color 0B

echo.
echo ====================================================================
echo           MT5 Trading Platform - System Diagnostics
echo ====================================================================
echo.
echo Running comprehensive system check...
echo.

cd /d "%~dp0"

REM ============================================================
REM Python Check
REM ============================================================
echo [Python]
python --version 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Status: ✓ Installed
    python -c "import sys; print('   Path:', sys.executable)"
) else (
    echo Status: ❌ NOT FOUND
    echo Action: Install from https://www.python.org/downloads/
)
echo.

REM ============================================================
REM Dependencies Check
REM ============================================================
echo [Dependencies]
pip show streamlit >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo Streamlit: ✓ Installed
    pip show streamlit | findstr "Version:"
) else (
    echo Streamlit: ❌ NOT INSTALLED
)

pip show MetaTrader5 >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo MetaTrader5: ✓ Installed
    pip show MetaTrader5 | findstr "Version:"
) else (
    echo MetaTrader5: ❌ NOT INSTALLED
)

pip show python-dotenv >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo python-dotenv: ✓ Installed
    pip show python-dotenv | findstr "Version:"
) else (
    echo python-dotenv: ❌ NOT INSTALLED
)
echo.

REM ============================================================
REM Configuration Check
REM ============================================================
echo [Configuration]
if exist ".env" (
    echo .env file: ✓ Found
    echo Config path: %CD%\.env
) else (
    echo .env file: ⚠ NOT FOUND
    if exist ".env.example" (
        echo .env.example: ✓ Found (you can copy this to .env)
    ) else (
        echo .env.example: ❌ NOT FOUND
    )
)
echo.

REM ============================================================
REM Directory Structure
REM ============================================================
echo [Directory Structure]
if exist "src" (
    echo src/: ✓ Found
) else (
    echo src/: ❌ MISSING
)

if exist "components" (
    echo components/: ✓ Found
) else (
    echo components/: ❌ MISSING
)

if exist "logs" (
    echo logs/: ✓ Found
    for %%F in (logs\*.log) do (
        echo    - %%~nxF ^(%%~zF bytes^)
    )
) else (
    echo logs/: ⚠ NOT CREATED YET
)

if exist "data" (
    echo data/: ✓ Found
) else (
    echo data/: ⚠ NOT CREATED YET
)
echo.

REM ============================================================
REM MT5 Terminal Check
REM ============================================================
echo [MetaTrader 5]
tasklist /FI "IMAGENAME eq terminal64.exe" 2>NUL | find /I /N "terminal64.exe">NUL
if %ERRORLEVEL% EQU 0 (
    echo Terminal: ✓ RUNNING
    tasklist /FI "IMAGENAME eq terminal64.exe" /FO LIST | findstr "PID:"
) else (
    echo Terminal: ⚠ NOT RUNNING
    echo Action: Start MetaTrader 5 Terminal
)
echo.

REM ============================================================
REM MT5 Sets Directory Check
REM ============================================================
echo [MT5 Sets Directory]
set DEFAULT_SETS=C:\Users\gamparo\Desktop\Projects\advanced_fibonacci_pro_v7\mt5\portafolio_manager\sets
if exist "%DEFAULT_SETS%" (
    echo Default path: ✓ EXISTS
    echo Path: %DEFAULT_SETS%
    dir /b "%DEFAULT_SETS%\*.set" 2>nul | find /c /v "" > temp_count.txt
    set /p SET_COUNT=<temp_count.txt
    del temp_count.txt
    echo Set files: Found
) else (
    echo Default path: ❌ NOT FOUND
    echo Path: %DEFAULT_SETS%
    echo Action: Update MT5_SETS_PATH in .env file
)
echo.

REM ============================================================
REM Network Check
REM ============================================================
echo [Network]
echo Checking localhost:8501 availability...
netstat -an | findstr "8501" >nul
if %ERRORLEVEL% EQU 0 (
    echo Port 8501: ⚠ ALREADY IN USE
    echo Action: Close existing Streamlit instance or use different port
) else (
    echo Port 8501: ✓ Available
)
echo.

REM ============================================================
REM Recent Logs Check
REM ============================================================
echo [Recent Logs]
if exist "logs\mt5_platform_errors.log" (
    echo Checking for recent errors...
    for /f "delims=" %%i in ('powershell -command "& {Get-Content logs\mt5_platform_errors.log -Tail 5 -ErrorAction SilentlyContinue}"') do (
        echo    %%i
    )
) else (
    echo No error log found yet
)
echo.

REM ============================================================
REM Summary
REM ============================================================
echo ====================================================================
echo                          SUMMARY
echo ====================================================================
echo.
echo If you see issues above:
echo.
echo 1. Missing Python: Install from python.org
echo 2. Missing dependencies: Run "pip install -r requirements.txt"
echo 3. Missing .env: Copy .env.example to .env
echo 4. MT5 not running: Start MetaTrader 5 Terminal
echo 5. Sets path wrong: Update MT5_SETS_PATH in .env
echo.
echo For detailed help, see UPGRADE_GUIDE.md
echo.
echo ====================================================================
echo.
pause
