
import os
import rpyc

MT5_HOST = os.getenv("MT5_HOST", "mt5")
MT5_PORT = int(os.getenv("MT5_PORT", 8001))

def verify():
    try:
        conn = rpyc.classic.connect(MT5_HOST, MT5_PORT)
        mt5 = conn.modules.MetaTrader5
        if not mt5.initialize(): return

        ti = mt5.terminal_info()
        print(f"Max bars: {ti.maxbars}")

    except Exception as e:
        print(e)

if __name__ == "__main__":
    verify()
