@echo off
echo ============================================================================
echo INSTITUTIONAL EDGE PRO - STARTUP MENU
echo ============================================================================
echo.
echo Select mode:
echo.
echo [1] Quick Backtest (1 Year - Fast ~15 min)
echo [2] Full Backtest (3 Years - Complete ~45 min)
echo [3] Live Trading System (Backend + Frontend + Worker)
echo [4] Full Suite (Backtest + Live Trading)
echo [5] Exit
echo.
set /p choice="Enter your choice (1-5): "

if "%choice%"=="1" goto backtest_fast
if "%choice%"=="2" goto backtest_full
if "%choice%"=="3" goto live_trading
if "%choice%"=="4" goto full_suite
if "%choice%"=="5" goto end

echo Invalid choice. Exiting...
goto end

:backtest_fast
echo.
echo ============================================================================
echo MODE: QUICK BACKTEST (1 Year - 2023)
echo ============================================================================
echo.
echo Running FAST strategy validation...
echo Period: 2023 only (~8,760 bars)
echo Estimated time: 15-20 minutes
echo.
cd backend
start "Institutional Edge - Quick Backtest" cmd /k "python run_backtest_fast.py"
cd ..
echo.
echo Quick backtest window launched!
echo Check backend\reports\ for results when complete.
echo.
pause
goto end

:backtest_full
echo.
echo ============================================================================
echo MODE: FULL BACKTEST (3 Years - 2021-2023)
echo ============================================================================
echo.
echo Running COMPLETE strategy validation...
echo Period: 2021-2023 (~26,280 bars)
echo Estimated time: 45-60 minutes
echo.
cd backend
start "Institutional Edge - Full Backtest" cmd /k "python run_backtest.py"
cd ..
echo.
echo Full backtest window launched!
echo Check backend\reports\ for results when complete.
echo.
pause
goto end

:live_trading
echo.
echo ============================================================================
echo MODE: LIVE TRADING SYSTEM
echo ============================================================================
echo.
echo [1/4] Starting Infrastructure (DB, Redis, RabbitMQ)...
echo ----------------------------------------------------------------
docker-compose up -d postgres redis rabbitmq pgadmin

echo.
echo Waiting 5 seconds for services to initialize...
timeout /t 5 /nobreak >nul

echo.
echo [2/4] Launching Backend API (Local)...
echo --------------------------------------
start "Institutional Edge - Backend" cmd /k "run_backend.bat"

echo.
echo [3/4] Launching Frontend (Local)...
echo -----------------------------------
cd frontend
start "Institutional Edge - Frontend" cmd /k "npm run dev"
cd ..

echo.
echo [4/4] Launching Trade Worker (Local)...
echo ---------------------------------------
start "Institutional Edge - Worker" cmd /k "run_worker.bat"

echo.
echo ============================================================================
echo LIVE TRADING SYSTEM STARTED SUCCESSFULLY!
echo ============================================================================
echo.
echo Frontend UI:      http://localhost:5173
echo Backend API:      http://localhost:8000/docs
echo RabbitMQ:         http://localhost:15672
echo.
echo All services are running in separate windows.
echo.
pause
goto end

:full_suite
echo.
echo ============================================================================
echo MODE: FULL SUITE (Backtest + Live Trading)
echo ============================================================================
echo.
echo Choose backtest speed:
echo [1] Quick (1 year - 15 min)
echo [2] Full (3 years - 45 min)
echo.
set /p bt_choice="Enter choice (1-2): "

echo.
echo Step 1: Running Backtest First...
echo ----------------------------------------------------------------
cd backend
if "%bt_choice%"=="1" (
    start "Institutional Edge - Quick Backtest" cmd /k "python run_backtest_fast.py"
) else (
    start "Institutional Edge - Full Backtest" cmd /k "python run_backtest.py"
)
cd ..

echo.
echo Waiting 10 seconds for backtest window to open...
timeout /t 10 /nobreak >nul

echo.
echo Step 2: Starting Live Trading Infrastructure...
echo ----------------------------------------------------------------
echo.
echo [1/4] Starting Infrastructure (DB, Redis, RabbitMQ)...
docker-compose up -d postgres redis rabbitmq pgadmin

echo.
echo Waiting 5 seconds for services to initialize...
timeout /t 5 /nobreak >nul

echo.
echo [2/4] Launching Backend API (Local)...
echo --------------------------------------
start "Institutional Edge - Backend" cmd /k "run_backend.bat"

echo.
echo [3/4] Launching Frontend (Local)...
echo -----------------------------------
cd frontend
start "Institutional Edge - Frontend" cmd /k "npm run dev"
cd ..

echo.
echo [4/4] Launching Trade Worker (Local)...
echo ---------------------------------------
start "Institutional Edge - Worker" cmd /k "run_worker.bat"

echo.
echo ============================================================================
echo FULL SUITE STARTED SUCCESSFULLY!
echo ============================================================================
echo.
echo BACKTEST:         Check separate window for results
echo REPORTS:          backend\reports\
echo.
echo LIVE TRADING:
echo Frontend UI:      http://localhost:5173
echo Backend API:      http://localhost:8000/docs
echo RabbitMQ:         http://localhost:15672
echo.
echo All services are running in separate windows.
echo.
echo IMPORTANT: Review backtest results before enabling live trading!
echo.
pause
goto end

:end
