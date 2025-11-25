@echo off
echo ============================================================================
echo INSTITUTIONAL EDGE PRO - MASTER STARTUP
echo ============================================================================

echo.
echo [1/3] Restarting Database & Redis (Docker)...
echo --------------------------------------------
docker-compose down
docker-compose up -d --build

echo.
echo Waiting 5 seconds for Database to initialize...
timeout /t 5 /nobreak >nul

echo.
echo [2/3] Launching Backend Server...
echo --------------------------------------------
start "Institutional Edge - Backend" cmd /k "run_backend.bat"

echo.
echo [3/3] Launching Frontend Dashboard...
echo --------------------------------------------
start "Institutional Edge - Frontend" cmd /k "run_frontend.bat"

echo.
echo ============================================================================
echo SYSTEM STARTED SUCCESSFULLY!
echo ============================================================================
echo.
echo Backend API:      http://localhost:8000/docs
echo Frontend UI:      http://localhost:5173
echo PgAdmin:          http://localhost:5050
echo.
echo Keep this window open or close it - the services are running in new windows.
echo.
pause
