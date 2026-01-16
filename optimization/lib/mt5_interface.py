import os
import subprocess
import time
import xml.etree.ElementTree as ET

# ⚠️ Configure Path
MT5_TERMINAL_PATH = r"C:\Program Files\MetaTrader 5\terminal64.exe"

def create_tester_ini(ini_path, ea_path, symbol, timeframe, date_from, date_to, deposit, report_path, params):
    """Generates tester.ini for MT5 CLI"""
    config = f"""
[Tester]
Expert={ea_path}
Symbol={symbol}
Period={timeframe}
Optimization=0
Model=1
FromDate={date_from}
ToDate={date_to}
ForwardMode=0
Deposit={deposit}
Currency=USD
Leverage=500
ExecutionMode=0
Report={report_path}
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
"""
    # Append Inputs dynamically
    for key, value in params.items():
        # Handle bools (true/false) vs numbers
        if isinstance(value, bool):
            val_str = "true" if value else "false"
        else:
            val_str = str(value)
        config += f"{key}={val_str}\n"

    with open(ini_path, "w") as f:
        f.write(config)

def parse_report_profit_factor(report_path):
    """Parses Profit Factor from MT5 XML Report"""
    if not os.path.exists(report_path):
        return 0.0

    try:
        # MT5 XML parsing (Robust implementation)
        tree = ET.parse(report_path)
        root = tree.getroot()
        
        # Look for "Profit Factor" in <UnorderedList> or similar structures
        # Strategy: Iterate text to find "Profit Factor" label
        for item in root.iter():
            # In many reports, it's Item -> Title: "Profit Factor", Value: "1.5"
            # Or table based.
            # Simplified search for now:
            if item.tag == "Item":
                title = item.find("Title")
                if title is not None and "Profit Factor" in title.text:
                    return float(item.find("Value").text)
        
        # Fallback: Net Profit?
        # For robustness, if PF not found, return 0
        return 0.0
        
    except Exception as e:
        print(f"Error parsing report: {e}")
        return 0.0

def run_mt5_test(ini_path, report_path):
    """Runs MT5 and waits for report"""
    if os.path.exists(report_path):
        os.remove(report_path)

    cmd = [MT5_TERMINAL_PATH, f"/config:{ini_path}"]
    
    try:
        subprocess.run(cmd, capture_output=True, text=True)
    except Exception as e:
        print(f"MT5 Launch Failed: {e}")
        return False
        
    # Wait loop
    max_wait = 600
    elapsed = 0
    while not os.path.exists(report_path):
        time.sleep(1)
        elapsed += 1
        if elapsed > max_wait:
            return False
            
    return True
