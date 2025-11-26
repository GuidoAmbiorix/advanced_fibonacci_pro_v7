@echo off
echo ============================================================================
echo INSTITUTIONAL EDGE PRO - DATABASE SEEDER
echo ============================================================================
echo.
echo This script will populate the database with default data.
echo Useful after resetting Docker volumes.
echo.

cd backend
python seed_db.py

echo.
pause
