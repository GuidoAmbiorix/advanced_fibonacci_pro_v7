
import requests
import json
import datetime

url = "http://localhost:8000/api/backtest/run"
payload = {
    "symbol": "EURUSD", 
    "timeframe": "H1", 
    "risk_percent": 1.0, 
    "tp_ratio": 2.0, 
    "sl_atr_multiplier": 1.5, 
    "strategy_mode": "SWING", 
    "start_date": "2024-01-01T00:00:00", 
    "end_date": "2024-01-05T00:00:00", 
    "enable_vwap_strategy": True, 
    "enable_stoch_strategy": True, 
    "enable_institutional_strategy": True, 
    "enable_fibonacci_strategy": True, 
    "engine_type": "GOLDEN", 
    "engine_config": {
        "structure": {"zigzag_lookback": 5}, 
        "risk": {"risk_percent": 1.0, "atr_sl_multiplier": 1.5}
    }
}

try:
    print(f"Sending request to {url}...")
    response = requests.post(url, json=payload)
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.text}")
except Exception as e:
    print(f"Error: {e}")
