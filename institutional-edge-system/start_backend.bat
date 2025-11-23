@echo off
echo Starting Institutional Edge PRO Backend...

cd /d "%~dp0backend\app"
set PYTHONPATH=%~dp0backend\app

python main.py

pause
