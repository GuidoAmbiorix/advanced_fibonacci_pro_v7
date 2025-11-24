@echo off
echo ============================================================================
echo Institutional Edge PRO - System Startup
echo ============================================================================
echo.

REM Check if Docker is running
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Docker is not running!
    echo Please start Docker Desktop and try again.
    pause
    exit /b 1
)

echo [1/4] Starting Docker containers...
docker-compose up -d

echo.
echo [2/4] Waiting for database to be ready...
timeout /t 5 /nobreak >nul

echo.
echo [3/4] Checking database status...
docker-compose ps

echo.
echo [4/4] System is ready!
echo.
echo ============================================================================
echo Access Points:
echo ============================================================================
echo API Documentation: http://localhost:8000/docs
echo Frontend Dashboard: http://localhost:5173
echo PgAdmin: http://localhost:5050
echo ============================================================================
echo.
echo Next steps:
echo 1. Run 'python init_db.py' to initialize the database (first time only)
echo 2. Run 'cd backend/app && python main.py' to start the API
echo 3. Run 'cd frontend && npm run dev' to start the dashboard
echo.
echo To stop: Run 'stop_system.bat' or 'docker-compose down'
echo.

pause
