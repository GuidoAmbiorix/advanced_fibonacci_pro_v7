"""
MQL5 Compile API Server
Exposes endpoints to compile .mq5 files using MetaEditor
"""
import os
import subprocess
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
import uvicorn

app = FastAPI(title="MT5 Compile API", version="1.0")

# Configuration
# Configuration
WINE_PREFIX = os.environ.get("WINEPREFIX", "/config/.wine")
MT5_PATH = f"{WINE_PREFIX}/drive_c/Program Files/MetaTrader 5"
METAEDITOR = f"{MT5_PATH}/MetaEditor64.exe"
DATA_DIR = "/data"
EA_SOURCES = f"{DATA_DIR}/ea_sources"
EA_COMPILED = f"{DATA_DIR}/ea_compiled"

# Store last compilation log
last_log = {"file": "", "output": "", "success": False}

@app.get("/")
def root():
    return {"status": "MT5 Compile API Running", "version": "1.0"}

@app.get("/status")
def status():
    """Check if MetaEditor is available"""
    exists = os.path.exists(f"{WINE_PREFIX}/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe")
    return {
        "metaeditor_installed": exists,
        "wine_prefix": WINE_PREFIX,
        "ea_sources_path": EA_SOURCES,
        "ea_compiled_path": EA_COMPILED
    }

@app.get("/files")
def list_files():
    """List available .mq5 files"""
    try:
        mq5_files = [f for f in os.listdir(EA_SOURCES) if f.endswith(".mq5")]
        ex5_files = [f for f in os.listdir(EA_COMPILED) if f.endswith(".ex5")]
        return {
            "sources": mq5_files,
            "compiled": ex5_files
        }
    except Exception as e:
        return {"error": str(e), "sources": [], "compiled": []}

@app.get("/compile")
def compile_file(file: str):
    """
    Compile a .mq5 file to .ex5
    
    Usage: GET /compile?file=MyBot.mq5
    """
    global last_log
    
    # Validate filename
    if not file.endswith(".mq5"):
        raise HTTPException(400, "File must be a .mq5 file")
    
    source_path = os.path.join(EA_SOURCES, file)
    
    if not os.path.exists(source_path):
        raise HTTPException(404, f"File not found: {file}")
    
    # Wine path conversion
    wine_source = f"Z:{source_path}"
    
    # Build compile command
    # Run wine as 'abc' user since that's who owns the Wine prefix
    # metaeditor64.exe /compile:"path" /log
    cmd = [
        "sudo", "-u", "abc",
        "wine",
        f"{WINE_PREFIX}/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe",
        f"/compile:{wine_source}",
        "/log"
    ]
    
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,
            env={**os.environ, "DISPLAY": ":0", "WINEPREFIX": WINE_PREFIX}
        )
        
        output = result.stdout + result.stderr
        success = result.returncode == 0
        
        # Check if .ex5 was created
        ex5_name = file.replace(".mq5", ".ex5")
        # MetaEditor outputs to same directory as source
        compiled_path = os.path.join(EA_SOURCES, ex5_name)
        
        if os.path.exists(compiled_path):
            # Move to compiled directory
            target_path = os.path.join(EA_COMPILED, ex5_name)
            os.rename(compiled_path, target_path)
            success = True
            output += f"\n\n✅ Output: {target_path}"
        
        last_log = {
            "file": file,
            "output": output,
            "success": success
        }
        
        return {
            "file": file,
            "success": success,
            "output": output
        }
        
    except subprocess.TimeoutExpired:
        last_log = {"file": file, "output": "Compilation timed out", "success": False}
        raise HTTPException(504, "Compilation timed out")
    except Exception as e:
        last_log = {"file": file, "output": str(e), "success": False}
        raise HTTPException(500, str(e))

@app.get("/log")
def get_log():
    """Get last compilation log"""
    return last_log

# ===== BACKTEST API =====
from pydantic import BaseModel
from typing import Dict, Any
import time
import xml.etree.ElementTree as ET

class BacktestRequest(BaseModel):
    ea_path: str
    symbol: str
    timeframe: str
    date_from: str
    date_to: str
    deposit: int
    parameters: Dict[str, Any]

@app.post("/backtest")
def run_backtest(request: BacktestRequest):
    """
    Run MT5 backtest via Wine
    Returns profit factor
    """
    import uuid
    test_id = uuid.uuid4().hex[:8]
    
    # Paths
    ini_path = f"/tmp/tester_{test_id}.ini"
    report_path = f"/tmp/report_{test_id}.xml"
    
    try:
        # Create INI file
        config = f"""[Tester]
Expert={request.ea_path}
Symbol={request.symbol}
Period={request.timeframe}
Optimization=0
Model=1
FromDate={request.date_from}
ToDate={request.date_to}
ForwardMode=0
Deposit={request.deposit}
Currency=USD
Leverage=500
ExecutionMode=0
Report={report_path}
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
"""
        for key, value in request.parameters.items():
            val_str = "true" if value is True else "false" if value is False else str(value)
            config += f"{key}={val_str}\n"
        
        with open(ini_path, "w") as f:
            f.write(config)
        
        # Run MT5 as abc user
        terminal_path = f"{WINE_PREFIX}/drive_c/Program Files/MetaTrader 5/terminal64.exe"
        
        cmd = [
            "sudo", "-u", "abc",
            "wine", terminal_path,
            f"/config:{ini_path}"
        ]
        
        env = {
            **os.environ,
            "DISPLAY": ":0",
            "WINEPREFIX": WINE_PREFIX
        }
        
        # Run backtest
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600, env=env)
        
        # Wait for report
        max_wait = 120
        elapsed = 0
        while not os.path.exists(report_path) and elapsed < max_wait:
            time.sleep(1)
            elapsed += 1
        
        # Parse profit factor
        profit_factor = 0.0
        if os.path.exists(report_path):
            try:
                tree = ET.parse(report_path)
                root = tree.getroot()
                
                for item in root.iter():
                    if item.tag == "Item":
                        title = item.find("Title")
                        if title is not None and "Profit Factor" in title.text:
                            value_elem = item.find("Value")
                            if value_elem is not None:
                                profit_factor = float(value_elem.text)
                                break
            except Exception as e:
                print(f"Report parse error: {e}")
        
        # Cleanup
        for path in [ini_path, report_path]:
            if os.path.exists(path):
                try:
                    os.remove(path)
                except:
                    pass
        
        return {
            "success": True,
            "profit_factor": profit_factor,
            "output": result.stdout + result.stderr
        }
        
    except subprocess.TimeoutExpired:
        raise HTTPException(504, "Backtest timed out (10 min limit)")
    except Exception as e:
        raise HTTPException(500, str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
