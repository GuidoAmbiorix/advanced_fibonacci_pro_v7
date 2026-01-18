"""
MT5 Backtest API - Extension to compile_api.py
Runs MT5 backtests via Wine and returns profit factor
"""
import os
import subprocess
import time
import xml.etree.ElementTree as ET
from fastapi import HTTPException
from pydantic import BaseModel
from typing import Dict, Any

class BacktestRequest(BaseModel):
    ea_path: str
    symbol: str
    timeframe: str
    date_from: str  # Format: YYYY.MM.DD
    date_to: str    # Format: YYYY.MM.DD
    deposit: int
    parameters: Dict[str, Any]

def create_tester_ini(ini_path, ea_path, symbol, timeframe, date_from, date_to, deposit, report_path, params):
    """Generates tester.ini for MT5 CLI"""
    config = f"""[Tester]
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
        tree = ET.parse(report_path)
        root = tree.getroot()
        
        for item in root.iter():
            if item.tag == "Item":
                title = item.find("Title")
                if title is not None and "Profit Factor" in title.text:
                    value_elem = item.find("Value")
                    if value_elem is not None:
                        return float(value_elem.text)
        
        return 0.0
        
    except Exception as e:
        print(f"Error parsing report: {e}")
        return 0.0
