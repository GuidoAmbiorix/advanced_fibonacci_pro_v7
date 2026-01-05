
import urllib.request
import json

# Assuming the endpoint is /api/slots/ (based on slots.py router)
# The slots router is likely mounted under /api/slots in main.py
url = "http://localhost:8000/api/slots/"

# Need to handle potential auth or just try public access if no deps?
# slots.py uses Depends(get_db), usually no auth for list unless specified in main.py
# Let's try simple GET first.

try:
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode('utf-8'))
        print(f"Status: {response.status}")
        print(f"Slots Found: {len(data)}")
        if len(data) > 0:
            s = data[0]
            print(f"Slot 1 Keys Sample: {list(s.keys())}")
            print(f"Risk: {s.get('risk_percent')}")
            print(f"MACD: {s.get('macd_fast')}/{s.get('macd_slow')}")
            print(f"SMC: OB={s.get('enable_order_blocks')} FVG={s.get('fvg_min_size_atr')}")
except Exception as e:
    print(f"Error: {e}")
