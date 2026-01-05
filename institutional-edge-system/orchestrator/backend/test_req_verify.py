
import urllib.request
import json

url = "http://localhost:8000/api/trading/start"
payload = {"account_id": 1, "symbol": "XAUUSD"}
data = json.dumps(payload).encode('utf-8')
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})

try:
    with urllib.request.urlopen(req) as response:
        resp_data = json.loads(response.read().decode('utf-8'))
        print(f"Success: {resp_data['success']}")
        config = resp_data.get('config', {})
        print(f"Session Mode: {config.get('trading_session', 'UNKNOWN')}")
        print(f"Engine Type: {config.get('engine_type', 'UNKNOWN')}")
        print(f"Risk Percent: {config.get('risk_percent', 'UNKNOWN')}")
except Exception as e:
    print(f"Error: {e}")
