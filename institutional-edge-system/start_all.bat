@echo off
echo ============================================================================
echo INSTITUTIONAL EDGE PRO - HYBRID STARTUP
echo ============================================================================

echo.
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
echo SYSTEM STARTED SUCCESSFULLY!
echo ============================================================================
echo.
echo Frontend UI:      http://localhost:5173
echo Backend API:      http://localhost:8000/docs
echo RabbitMQ:         http://localhost:15672
echo.
echo All services are running in separate windows.
echo.
pause
