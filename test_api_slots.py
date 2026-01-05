import requests
import json
from datetime import datetime

# Helper to serialize datetime objects for printing
def json_serial(obj):
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError ("Type %s not serializable" % type(obj))

def test_slots_endpoint():
    try:
        response = requests.get('http://localhost:81/api/slots/')
        if response.status_code == 200:
            slots = response.json()
            print(f"Successfully retrieved {len(slots)} slots.")
            for slot in slots:
                print(f"\n--- Slot ID: {slot.get('id')} Symbol: {slot.get('symbol')} ---")
                
                # Check for critical fields that were missing before
                critical_fields = [
                    'macd_fast', 'macd_slow', 'risk_percent', 
                    'zigzag_lookback', 'enable_order_blocks', 
                    'trading_session', 'session_end_action'
                ]
                
                missing = []
                for field in critical_fields:
                    if field not in slot:
                        missing.append(field)
                
                if missing:
                    print(f"❌ MISSING FIELDS: {missing}")
                else:
                    print("✅ All critical fields present.")
                    
                # Print specific values to verify seeding
                print(f"Risk: {slot.get('risk_percent')}%")
                print(f"MACD: {slot.get('macd_fast')}/{slot.get('macd_slow')}/{slot.get('macd_signal')}")
                print(f"ZigZag: {slot.get('zigzag_lookback')}")
                print(f"Session: {slot.get('trading_session')}")
                
                # Dump full slot for inspection if needed (commented out to avoid clutter)
                # print(json.dumps(slot, indent=2, default=json_serial))
                
        else:
            print(f"❌ Failed to retrieve slots. Status Code: {response.status_code}")
            print(response.text)
            
    except Exception as e:
        print(f"❌ Exception occurred: {e}")

if __name__ == "__main__":
    test_slots_endpoint()
