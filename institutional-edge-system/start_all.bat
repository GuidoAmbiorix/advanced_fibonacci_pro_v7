@echo off
REM ============================================================================
REM INSTITUTIONAL EDGE PRO - Unified Startup Script
REM ============================================================================
REM Complete infrastructure: 14 services in one docker-compose.yml
REM ============================================================================

echo =========================================
echo Institutional Edge Pro - System Startup
echo =========================================
echo.

REM 1. Create Directories
echo [1/4] Creating directories...
if not exist "nginx\logs" mkdir nginx\logs
if not exist "logs" mkdir logs
if not exist "backend\logs" mkdir backend\logs
if not exist "monitoring" mkdir monitoring

REM 2. Check Docker
echo [2/4] Checking Docker status...
docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker is not running. Please start Docker Desktop and try again.
    pause
    exit /b 1
)
echo   [OK] Docker is running

REM 3. Start All Services
echo [3/4] Starting all 14 services...
docker compose up -d --build
if errorlevel 1 (
    echo [ERROR] Failed to start services.
    pause
    exit /b 1
)
echo   [OK] All services started

REM 4. Wait for Health
echo [4/4] Waiting for services to initialize...
timeout /t 15 /nobreak >nul

echo.
echo Checking service health...
echo -----------------------------------------

REM Check PostgreSQL
docker exec trading_postgres pg_isready -U trading >nul 2>&1
if errorlevel 1 (
    echo   [WARN] PostgreSQL not ready yet
) else (
    echo   [OK] PostgreSQL is healthy
)

REM Check Redis
docker exec trading_redis redis-cli ping >nul 2>&1
if errorlevel 1 (
    echo   [WARN] Redis not responding
) else (
    echo   [OK] Redis is healthy
)

REM Check Backend
curl -s http://localhost:8000/health >nul 2>&1
if errorlevel 1 (
    echo   [WARN] Backend not responding yet
) else (
    echo   [OK] Backend API is healthy
)

REM Check Nginx
curl -s http://localhost/health >nul 2>&1
if errorlevel 1 (
    echo   [WARN] Nginx not responding yet
) else (
    echo   [OK] Nginx proxy is healthy
)

REM Check Prometheus
curl -s http://localhost:9090/-/healthy >nul 2>&1
if errorlevel 1 (
    echo   [WARN] Prometheus not responding yet
) else (
    echo   [OK] Prometheus is healthy
)

REM Check Grafana
curl -s http://localhost:3002/api/health >nul 2>&1
if errorlevel 1 (
    echo   [WARN] Grafana not responding yet
) else (
    echo   [OK] Grafana is healthy
)

echo.
echo =========================================
echo SYSTEM READY
echo =========================================
echo.
echo Access URLs:
echo -----------------------------------------
echo Frontend:        http://localhost/
echo Backend API:     http://localhost/api/
echo MT5 VNC:         http://localhost:3000/
echo.
echo Monitoring:
echo -----------------------------------------
echo Grafana:         http://localhost:3002/ (admin/admin)
echo Prometheus:      http://localhost:9090/
echo RabbitMQ UI:     http://localhost:15672/ (guest/guest)
echo PGAdmin:         http://localhost:5050/ (admin@trading.com/admin)
echo.
echo To view logs:
echo   docker compose logs -f backend
echo   docker compose logs -f postgres
echo.
echo To stop everything:
echo   docker compose down
echo.
pause
