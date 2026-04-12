@echo off
REM ============================================================================
REM INSTITUTIONAL EDGE PRO - Startup Script
REM ============================================================================

echo =========================================
echo   Institutional Edge Pro - Starting...
echo =========================================
echo.

REM Check Docker
docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker is not running. Start Docker Desktop and try again.
    pause
    exit /b 1
)

REM Create log directories
if not exist "logs" mkdir logs

REM Build and start all services
echo Starting all services...
docker compose up -d --build
if errorlevel 1 (
    echo [ERROR] Failed to start services. Check docker compose logs.
    pause
    exit /b 1
)

echo.
echo =========================================
echo   SYSTEM READY
echo =========================================
echo.
echo Access URLs:
echo   Dashboard:    http://localhost:80
echo   Backend API:  http://localhost:8000
echo   MT5 VNC:      http://localhost:3000  (password: trading)
echo   RabbitMQ UI:  http://localhost:15672  (guest/guest)
echo.
echo To stop:  docker compose down
echo Logs:     docker compose logs -f
echo.
pause
