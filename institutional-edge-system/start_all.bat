@echo off
echo ============================================================================
echo INSTITUTIONAL EDGE PRO - HYBRID STARTUP
echo ============================================================================

echo.
echo [1/2] Starting Docker Services (Backend, Frontend, DB, Queue)...
echo ----------------------------------------------------------------
docker-compose down
docker-compose up -d --build

echo.
echo Waiting 10 seconds for services to initialize...
timeout /t 10 /nobreak >nul

echo.
echo [2/2] Launching Trade Worker (Local Host)...
echo --------------------------------------------
start "Institutional Edge - Worker" cmd /k "run_worker.bat"

echo.
echo ============================================================================
echo SYSTEM STARTED SUCCESSFULLY!
echo ============================================================================
echo.
echo Frontend UI:      http://localhost
echo Backend API:      http://localhost:8000/docs
echo RabbitMQ:         http://localhost:15672
echo.
echo The Worker is running in a separate window.
echo.
pause
