import os
import requests
import time

# MT5 API URL (the compile/backtest API running in the MT5 container)
MT5_API_URL = os.environ.get("MT5_API_URL", "http://mt5_terminal:8080")

def create_tester_ini(ini_path, ea_path, symbol, timeframe, date_from, date_to, deposit, report_path, params):
    """
    This function is kept for backward compatibility but is not used
    in the remote API approach. Parameters are sent via HTTP instead.
    """
    pass  # Not needed for remote API

def parse_report_profit_factor(report_path):
    """
    This function is kept for backward compatibility but is not used
    in the remote API approach. The API returns the profit factor directly.
    """
    return 0.0  # Not needed for remote API

def run_mt5_test(ini_path, report_path, ea_path=None, symbol=None, timeframe=None, 
                 date_from=None, date_to=None, deposit=None, params=None):
    """
    Runs MT5 backtest via the remote API in the MT5 container.
    
    For backward compatibility with the old interface, this function accepts both:
    - Old style: ini_path and report_path (ignored)
    - New style: all parameters directly
    
    Returns True if successful, False otherwise.
    """
    
    # If called with the new style (direct parameters), use them
    if ea_path and symbol and timeframe:
        try:
            # Call the remote backtest API
            response = requests.post(
                f"{MT5_API_URL}/backtest",
                json={
                    "ea_path": ea_path,
                    "symbol": symbol,
                    "timeframe": timeframe,
                    "date_from": date_from,
                    "date_to": date_to,
                    "deposit": deposit,
                    "parameters": params or {}
                },
                timeout=620  # 10 min + buffer
            )
            
            if response.ok:
                result = response.json()
                # Store profit factor in a way that can be retrieved
                global _last_profit_factor
                _last_profit_factor = result.get("profit_factor", 0.0)
                return result.get("success", False)
            else:
                print(f"Backtest API error: {response.status_code} - {response.text}")
                return False
                
        except requests.exceptions.Timeout:
            print("Backtest timed out (10 minutes)")
            return False
        except Exception as e:
            print(f"Backtest API call failed: {e}")
            return False
    
    # Old style call - not supported with remote API
    return False

# Global to store last profit factor (for compatibility with old interface)
_last_profit_factor = 0.0

def get_last_profit_factor():
    """Returns the profit factor from the last backtest"""
    global _last_profit_factor
    return _last_profit_factor
