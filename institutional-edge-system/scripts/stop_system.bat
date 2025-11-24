@echo off
echo ============================================================================
echo Institutional Edge PRO - System Shutdown
echo ============================================================================
echo.

echo Stopping Docker containers...
docker-compose down

echo.
echo ============================================================================
echo System stopped successfully!
echo ============================================================================
echo.
echo To start again: Run 'start_system.bat' or 'docker-compose up -d'
echo.

pause
