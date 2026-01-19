@echo off
TITLE Quantum Lab Controller
:MENU
CLS
echo ===================================================
echo 🧬 QUANTUM LAB & OPTIMIZER CONTROLLER
echo ===================================================
echo.
echo  [1] 🚀 Start Dashboard (Optuna + Visuals)
echo  [2] ⛏️ Run Data Miner (Download MT5 Data)
echo  [3] 🧬 Run Genetic Alpha Discovery (GPLearn)
echo  [4] 📦 Install Requirements
echo  [5] ❌ Exit
echo.
set /p choice="Select Option: "

if "%choice%"=="1" goto DASHBOARD
if "%choice%"=="2" goto DATA
if "%choice%"=="3" goto GENETIC
if "%choice%"=="4" goto INSTALL
if "%choice%"=="5" goto EXIT

:DASHBOARD
echo Starting Dashboard...
python -m streamlit run dashboard.py --server.port 8501
pause
goto MENU

:DATA
echo Starting Data Miner...
python quant_lab/data_miner.py
pause
goto MENU

:GENETIC
echo Starting Genetic Evolution...
python quant_lab/genetic_miner.py
pause
goto MENU

:INSTALL
pip install -r requirements.txt
pause
goto MENU

:EXIT
exit