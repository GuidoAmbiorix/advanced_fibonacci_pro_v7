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
WINE_PREFIX = os.environ.get("WINEPREFIX", "/home/mt5/.wine")
MT5_PATH = f"{WINE_PREFIX}/drive_c/Program Files/MetaTrader 5"
METAEDITOR = f"{MT5_PATH}/metaeditor64.exe"
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
    exists = os.path.exists(f"{WINE_PREFIX}/drive_c/Program Files/MetaTrader 5/metaeditor64.exe")
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
    # metaeditor64.exe /compile:"path" /log
    cmd = [
        "wine",
        f"{WINE_PREFIX}/drive_c/Program Files/MetaTrader 5/metaeditor64.exe",
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

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
