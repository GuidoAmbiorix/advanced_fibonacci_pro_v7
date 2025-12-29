@echo off
REM ============================================================================
REM INSTITUTIONAL EDGE PRO - Unified Startup Script
REM ============================================================================

echo =========================================
echo Institutional Edge Pro - System Startup
echo =========================================
echo.

REM 1. Create Log Directories
echo [1/5] Creating log directories...
if not exist "nginx\logs" mkdir nginx\logs
if not exist "logs" mkdir logs

REM 2. Check Docker
echo [2/5] Checking Docker status...
docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker is not running. Please start Docker Desktop and try again.
    pause
    exit /b 1
)

REM 3. Network Setup
echo [3/5] configuring network...
REM Check if network exists, if not create it
docker network inspect bot-net >nul 2>&1
if errorlevel 1 (
    echo   - Creating shared network 'bot-net'...
    docker network create bot-net
) else (
    echo   - Shared network 'bot-net' already exists.
)

docker network inspect trading_network >nul 2>&1
if errorlevel 1 (
    echo   - Creating shared network 'trading_network'...
    docker network create trading_network
) else (
    echo   - Shared network 'trading_network' already exists.
)

REM 4. Start Services
echo [4/5] Starting Services...

echo   - Starting Proxy Service...
docker-compose -f docker-compose.proxy.yml up -d
if errorlevel 1 (
    echo [ERROR] Failed to start Proxy.
    pause
    exit /b 1
)

echo   - Starting Shared Infrastructure (RabbitMQ)...
docker-compose -f docker-compose.shared.yml up -d
if errorlevel 1 (
    echo [ERROR] Failed to start Shared Infrastructure.
    pause
    exit /b 1
)

echo   - Starting Fleet Commander...
docker-compose -f docker-compose.admin.yml up -d
if errorlevel 1 (
    echo [ERROR] Failed to start Orchestrator.
    pause
    exit /b 1
)



REM 5. Wait for Health
echo [5/5] Waiting for services to initialize...
timeout /t 5 /nobreak >nul

REM Check Nginx Health
curl -s http://localhost/health >nul 2>&1
if errorlevel 1 (
    echo [WARNING] Proxy health check failed. Please check logs.
) else (
    echo [OK] Proxy is Healthy
)

echo.
echo =========================================
echo SYSTEM READY 🚀
echo =========================================
echo.
echo Access URLs:
echo -----------------------------------------
echo Fleet Commander: http://localhost:9000/
echo RabbitMQ:        http://localhost:15672/ (guest/guest)
echo.
echo Instance URLs (Once Deployed):
echo -----------------------------------------
echo Instance 1:     http://localhost:81/ (Dashboard) - VNC: 3001
echo Instance 2:     http://localhost:82/ (Dashboard) - VNC: 3002
echo.
echo NOTE: Each instance has its own dedicated MT5 terminal.
echo       Access VNC ports (3001+) to login to broker accounts.
echo.
echo To Stop Everything:
echo   docker-compose -f docker-compose.admin.yml down
echo   docker-compose -f docker-compose.proxy.yml down
echo   docker-compose -f docker-compose.shared.yml down
echo.
pause
