
import rpyc
import os
import time

MT5_HOST = os.getenv("MT5_HOST", "mt5")
MT5_PORT = int(os.getenv("MT5_PORT", 8001))

def test_order_send():
    print(f"Connecting to {MT5_HOST}:{MT5_PORT}...")
    try:
        conn = rpyc.classic.connect(MT5_HOST, MT5_PORT)
        mt5 = conn.modules.MetaTrader5
        
        if not mt5.initialize():
            print(f"MT5 Init failed: {mt5.last_error()}")
            return

        print("MT5 Initialized. Attempting order_send with dummy request...")
        
        # Create a dummy request (doesn't need to be valid, just needs to pass argument check)
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": "EURUSD",
            "volume": 0.01,
            "type": mt5.ORDER_TYPE_BUY,
            "price": 1.0,
            "deviation": 20,
            "magic": 123456,
            "comment": "Debug Test",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        
        print("1. Testing Positional Argument: mt5.order_send(request)")
        try:
            res = mt5.order_send(request)
            if res is None:
                print(f"Result is None. Last Error: {mt5.last_error()}")
            else:
                print(f"Result: {res}")
        except Exception as e:
            print(f"Exception during positional call: {e}")
            
        print("\n2. Testing Keyword Argument: mt5.order_send(request=request)")
        try:
            res = mt5.order_send(request=request)
            if res is None:
                print(f"Result is None. Last Error: {mt5.last_error()}")
            else:
                print(f"Result: {res}")
        except Exception as e:
            print(f"Exception during keyword call: {e}")

    except Exception as e:
        print(f"Connection failed: {e}")

if __name__ == "__main__":
    test_order_send()
