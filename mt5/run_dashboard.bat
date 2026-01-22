@echo off
TITLE Elite Trading Dashboard
cd /d "%~dp0streamlit_project"
echo ===================================================
echo 🚀 Launching Elite Trading Intelligence Platform...
echo ===================================================
echo.
python -m streamlit run app.py
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ❌ Error launching Streamlit. 
    echo Ensuring pip requirements...
    pip install -r requirements.txt
    echo Retrying...
    python -m streamlit run app.py
)
pause
