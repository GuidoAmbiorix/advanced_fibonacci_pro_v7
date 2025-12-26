
import sys
import json
import MetaTrader5 as mt5
import os
from datetime import datetime

def block_print():
    sys.stdout = open(os.devnull, 'w')

def enable_print():
    sys.stdout = sys.__stdout__

import tempfile

def log_debug(msg):
    try:
        temp_dir = tempfile.gettempdir()
        log_path = os.path.join(temp_dir, "verify_login_debug.log")
        with open(log_path, "a", encoding='utf-8') as f:
            f.write(f"{datetime.now().isoformat()} - {msg}\n")
    except:
        pass

def verify_login(login, password, server, terminal_path):
    log_debug(f"Starting verification for {login} on {server}")
    log_debug(f"Path: {terminal_path}")
    
    # Suppress MT5 startup junk output to keep JSON clean
    # block_print() 
    
    result = {
        "success": False,
        "balance": 0.0,
        "error": ""
    }
    
    try:
        # Initialize
        init_args = {}
        if terminal_path:
            if not terminal_path.endswith("terminal64.exe"):
                 terminal_path = os.path.join(terminal_path, "terminal64.exe")
            init_args['path'] = terminal_path
            
        log_debug(f"Initializing MT5 with args: {init_args}")
        if not mt5.initialize(**init_args):
            err = mt5.last_error()
            log_debug(f"MT5 Init Failed: {err}")
            result["error"] = f"MT5 Init Failed: {err}"
            return result

        log_debug("MT5 Initialized. Logging in...")
        # Login
        authorized = mt5.login(
            login=int(login),
            password=password,
            server=server
        )
        
        if authorized:
            log_debug("Login successful. fetching info...")
            info = mt5.account_info()
            if info:
                result["success"] = True
                result["balance"] = info.balance
                log_debug(f"Success. Balance: {info.balance}")
            else:
                 result["error"] = "Logged in but failed to get account info"
                 log_debug("Failed to get account info")
        else:
            err = mt5.last_error()
            log_debug(f"Login Failed: {err}")
            result["error"] = f"Login Failed: {err}"
            
    except Exception as e:
        log_debug(f"Exception: {e}")
        result["error"] = str(e)
    finally:
        mt5.shutdown()
        log_debug("MT5 Shutdown")
        # enable_print()
    
    return result

if __name__ == "__main__":
    try:
        # Expecting JSON input from stdin or arguments
        # python verify_login.py <login> <password> <server> <optional_path>
        
        if len(sys.argv) < 4:
            print(json.dumps({"success": False, "error": "Missing arguments"}))
            sys.exit(1)
            
        login = sys.argv[1]
        password = sys.argv[2]
        server = sys.argv[3]
        terminal_path = sys.argv[4] if len(sys.argv) > 4 else None
        
        output = verify_login(login, password, server, terminal_path)
        print(json.dumps(output))
        
    except Exception as e:
        print(json.dumps({"success": False, "error": f"Script Error: {str(e)}"}))
