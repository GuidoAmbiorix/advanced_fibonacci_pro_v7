@echo off
echo Starting Trade Worker...
cd backend
call venv\Scripts\activate
python -m app.worker
pause
