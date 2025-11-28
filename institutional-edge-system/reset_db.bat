@echo off
echo ============================================================================
echo RESETTING DATABASE (DELETING ALL DATA)
echo ============================================================================
echo.
echo [1/2] Stopping Containers and Removing Volumes...
docker-compose down -v

echo.
echo [2/2] Restarting Infrastructure...
docker-compose up -d postgres redis rabbitmq pgadmin

echo.
echo DONE! Database has been reset.
echo You can now run start_all.bat
pause
