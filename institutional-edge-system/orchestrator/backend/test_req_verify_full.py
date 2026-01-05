
import urllib.request
import json

url = "http://localhost:8000/api/trading/start"
payload = {"account_id": 1, "symbol": "XAUUSD"}
data = json.dumps(payload).encode('utf-8')
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})

try:
    with urllib.request.urlopen(req) as response:
        resp_data = json.loads(response.read().decode('utf-8'))
        config = resp_data.get('config', {})
        print(f"Success: {resp_data['success']}")
        print(f"Risk: {config.get('risk_percent')}")
        print(f"MACD: {config.get('macd_fast')}/{config.get('macd_slow')}/{config.get('macd_signal')}")
        print(f"RSI: {config.get('rsi_period')} (OB:{config.get('rsi_overbought')} OS:{config.get('rsi_oversold')})")
        print(f"ZigZag: {config.get('zigzag_lookback')}")
        print(f"SMC: OB={config.get('ob_lookback')} Sweep={config.get('sweep_lookback')} FVG={config.get('enable_fvg')}")
        print(f"Session: {config.get('trading_session')}")
except Exception as e:
    print(f"Error: {e}")
