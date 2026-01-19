from lib.python_backtester import get_backtester
import time

print("Testing RPyC Connection...")
backtester = get_backtester()

if backtester.connect():
    print("SUCCESS! Connected.")
    print("Testing data fetch...")
    data = backtester.get_historical_data("EURUSD", "H1", "2025-01-01", "2025-01-05")
    if data is not None:
        print(f"Data received: {len(data)} rows")
    else:
        print("Data fetch returned None (might range issues or symbols)")
else:
    print("FAILED to connect.")
