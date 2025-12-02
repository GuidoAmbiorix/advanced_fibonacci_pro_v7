@echo off
echo ============================================================================
echo INSTITUTIONAL EDGE PRO - STARTUP MENU
echo ============================================================================
echo.
echo Select mode:
echo.
echo [1] Backtest Only (Validate Strategy)
echo [2] Live Trading System (Backend + Frontend + Worker)
echo [3] Full Suite (Backtest + Live Trading)
echo [4] Exit
echo.
set /p choice="Enter your choice (1-4): "

if "%choice%"=="1" goto backtest_only
if "%choice%"=="2" goto live_trading
if "%choice%"=="3" goto full_suite
if "%choice%"=="4" goto end

echo Invalid choice. Exiting...
goto end

:backtest_only
echo.
echo ============================================================================
echo MODE: BACKTEST ONLY
echo ============================================================================
echo.
echo Running strategy validation backtest...
echo.
cd backend
start "Institutional Edge - Backtest" cmd /k "python run_backtest.py"
cd ..
echo.
echo Backtest window launched!
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
echo Step 1: Running Backtest First...
echo ----------------------------------------------------------------
cd backend
start "Institutional Edge - Backtest" cmd /k "python run_backtest.py"
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
