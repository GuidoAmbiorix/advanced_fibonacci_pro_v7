
import sys
import os
import requests
import json
from datetime import datetime

# URL for local API
API_URL = "http://localhost:81/api/slots/"

payload = {
    "bot_config_id": 1,
    "symbol": "EURUSD",
    "direction_filter": "BOTH",
    "timeframe": "M5",
    "risk_percent": 1.0,
    "tp_ratio": 2.0,
    "sl_atr_multiplier": 1.5,
    "tsl_mode": "TIERED",
    "rsi_period": 14,
    "rsi_overbought": 70,
    "rsi_oversold": 30,
    "min_confluence_score": 7,
    "max_trade_duration_hours": 2,
    "enable_vwap_strategy": True,
    "enable_stoch_strategy": True,
    "enable_institutional_strategy": True,
    "enable_fibonacci_strategy": True,
    "partial_tp_on": True,
    "partial_tp_amount": 1.0,
    "enabled": True,
    
    # Engine & Institutional Params
    "engine_type": "INSTITUTIONAL",
    "trading_session": "ALL",
    "session_end_action": "HOLD",
    "use_daily_bias": False,
    "confirmation_timeframe": None,
    
    # SMC
    "zigzag_lookback": 12,
    "enable_order_blocks": True,
    "ob_lookback": 20,
    "enable_liquidity_sweep": True,
    "sweep_lookback": 10,
    "enable_fvg": True,
    "fvg_min_size_atr": 0.5,
    
    # Filters
    "use_adx_filter": False,
    "use_h1_trend_filter": False,
    "vwap_use_trend_filter": True
}

try:
    print(f"Sending POST to {API_URL}...")
    response = requests.post(API_URL, json=payload)
    
    print(f"Status: {response.status_code}")
    try:
        print("Response:", response.json())
    except:
        print("Raw Response:", response.text)
        
except Exception as e:
    print(f"❌ Error: {e}")
