
import urllib.request
import json

url = "http://localhost:8000/api/trading/start"
payload = {"account_id": 1, "symbol": "XAUUSD"}
data = json.dumps(payload).encode('utf-8')
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})

try:
    with urllib.request.urlopen(req) as response:
        print(f"Status: {response.status}")
        print(response.read().decode('utf-8'))
except Exception as e:
    print(f"Error: {e}")
