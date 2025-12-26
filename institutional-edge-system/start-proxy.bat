@echo off
REM ============================================================================
REM INSTITUTIONAL EDGE PRO - Proxy Startup Script (Windows)
REM ============================================================================

echo =========================================
echo Institutional Edge Pro - Proxy Setup
echo =========================================
echo.

REM Create nginx logs directory
echo Creating nginx logs directory...
if not exist "nginx\logs" mkdir nginx\logs

REM Check if docker is running
docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker is not running. Please start Docker and try again.
    pause
    exit /b 1
)

echo [OK] Docker is running
echo.

REM Start nginx proxy
echo Starting nginx reverse proxy...
docker-compose -f docker-compose.proxy.yml up -d

REM Wait for nginx to start
echo Waiting for nginx to start...
timeout /t 3 /nobreak >nul

REM Check nginx health
curl -s http://localhost/health >nul 2>&1
if errorlevel 1 (
    echo [WARNING] Nginx proxy started but health check failed
    echo Checking logs...
    docker logs institutional_nginx_proxy --tail 20
    pause
    exit /b 1
)

echo [OK] Nginx proxy is running
echo.
echo =========================================
echo Proxy URLs:
echo =========================================
echo Health Check:     http://localhost/health
echo Orchestrator:     http://localhost/
echo Orchestrator API: http://localhost/api/orchestrator
echo.
echo Instance URLs (when instances are running):
echo Instance 1:       http://localhost/instance/1
echo Instance 2:       http://localhost/instance/2
echo Instance N:       http://localhost/instance/N
echo.
echo =========================================
echo Setup complete!
echo =========================================
echo.
echo Next steps:
echo 1. Create instances using the orchestrator
echo 2. Access instances through the proxy URLs above
echo.
echo To view logs:
echo   docker logs -f institutional_nginx_proxy
echo.
echo To stop the proxy:
echo   docker-compose -f docker-compose.proxy.yml down
echo.

pause
