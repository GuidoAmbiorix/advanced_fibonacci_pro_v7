import optuna
import os
import subprocess
import xml.etree.ElementTree as ET
import time
import shutil

# --- CONFIGURATION ---------------------------------------------------------
# ⚠️ YOU MUST SET THIS PATH TO YOUR MT5 INSTALLATION ⚠️
MT5_TERMINAL_PATH = r"C:\Program Files\MetaTrader 5\terminal64.exe"

# Project Paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(BASE_DIR)
EA_PATH = os.path.join(PROJECT_ROOT, "mt5", "Adaptive_Multi_Strategy.ex5")
TESTER_INI_PATH = os.path.join(BASE_DIR, "tester.ini")
REPORT_PATH = os.path.join(BASE_DIR, "report.xml")

# Trading Settings
SYMBOL = "XAUUSD"
TIMEFRAME = "M15"
DATE_FROM = "2024.01.01"
DATE_TO = "2024.12.31"
DEPOSIT = 10000

# ---------------------------------------------------------------------------

def create_tester_ini(params):
    """Generates the tester.ini file for MT5 CLI."""
    config = f"""
[Tester]
Expert={EA_PATH}
Symbol={SYMBOL}
Period={TIMEFRAME}
Optimization=0
Model=1
FromDate={DATE_FROM}
ToDate={DATE_TO}
ForwardMode=0
Deposit={DEPOSIT}
Currency=USD
Leverage=500
ExecutionMode=0
Report={REPORT_PATH}
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
InpRisk_Reward_Ratio={params['rr_ratio']:.2f}
InpMin_Confluence_Score={params['conf_score']:.1f}
InpSwap_Lookback={params['lookback']}
InpADX_Threshold={params['adx_threshold']}
InpCooldownMinutes={params['cooldown']}
InpContext_Lookback={params['context_lookback']}
InpTrailProfile={params['trail_profile']}
InpContext_Timeframe=PERIOD_H1
InpRisk_Per_Trade=0.5
InpEnable_Stochastic=false
    """
    with open(TESTER_INI_PATH, "w") as f:
        f.write(config)

def parse_report(report_path):
    """Parses the MT5 XML report to extract metrics."""
    if not os.path.exists(report_path):
        print("❌ Report not found!")
        return 0.0

    try:
        tree = ET.parse(report_path)
        root = tree.getroot()
        
        # MT5 XML structure can vary, but usually summary is in <Report> -> <Summary>
        # Finding ProfitFactor
        # Note: Depending on MT5 version, report might be HTML.
        # This parser assumes we can force XML or handle basic HTML scraping if needed.
        # For reliable CLI, usually Report type is controlled by extension.
        
        # Searching for keys in the summary table
        # Simplistic parsing for now:
        for item in root.iter("Item"):
            name = item.find("Title")
            if name is not None:
                if "Profit Factor" in name.text:
                    return float(item.find("Value").text)
                
        # Fallback if XML structure is complex:
        # Just return 0.0 or try to find "Total Net Profit"
        return 0.0
        
    except Exception as e:
        print(f"⚠️ Error parsing report: {e}")
        return 0.0

def objective(trial):
    """Optuna Objective Function"""
    
    # 1. Suggest Parameters
    params = {
        'rr_ratio': trial.suggest_float('rr_ratio', 2.0, 4.0, step=0.1),
        'conf_score': trial.suggest_float('conf_score', 5.5, 8.5, step=0.5),
        'lookback': trial.suggest_int('lookback', 8, 25),
        'adx_threshold': trial.suggest_int('adx_threshold', 20, 30),
        'cooldown': trial.suggest_int('cooldown', 15, 60, step=15),
        'context_lookback': trial.suggest_int('context_lookback', 20, 100, step=10),
        'trail_profile': trial.suggest_categorical('trail_profile', ['TRAIL_INTRADAY', 'TRAIL_SWING'])
    }
    
    print(f"\n🔄 Trial {trial.number}: Testing params {params}")
    
    # 2. Setup Config
    create_tester_ini(params)
    
    # 3. Clean previous report
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
        
    # 4. Run MT5 Strategy Tester
    # Command: terminal64.exe /config:path/to/ini /portable
    cmd = [MT5_TERMINAL_PATH, f"/config:{TESTER_INI_PATH}"]
    
    try:
        # Run and wait
        result = subprocess.run(cmd, capture_output=True, text=True)
        # MT5 usually returns immediately if passed to GUI, but /config should run tester.
        # We might need to wait loop for the report file to appear.
    except Exception as e:
        print(f"❌ Execution failed: {e}")
        return 0.0

    # Wait for report (max 600 seconds)
    max_wait = 600
    elapsed = 0
    print("    ⏳ Waiting for MT5...", end="", flush=True)
    while not os.path.exists(REPORT_PATH):
        time.sleep(1)
        print(".", end="", flush=True)
        elapsed += 1
        if elapsed > max_wait:
            print("\n❌ Timeout: MT5 took too long.")
            return 0.0
    print("") # New line
            
    # 5. Parse Result
    pf = parse_report(REPORT_PATH)
    print(f"✅ Result: Profit Factor = {pf}")
    
    return pf

if __name__ == "__main__":
    if not os.path.exists(MT5_TERMINAL_PATH):
        print(f"❌ ERROR: MT5 Terminal not found at {MT5_TERMINAL_PATH}")
        print("Please edit the script and set the correct path.")
        exit(1)
        
    print("🚀 Starting AI Optimization Engine...")
    print(f"📂 EA Path: {EA_PATH}")
    
    study = optuna.create_study(direction="maximize")
    study.optimize(objective, n_trials=20)
    
    print("\n🏆 Optimization Complete!")
    print(f"Best Params: {study.best_params}")
    print(f"Best Profit Factor: {study.best_value}")
