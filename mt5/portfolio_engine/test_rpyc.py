import rpyc
import sys

host = 'mt5'
port = 8001

print(f"Connecting to {host}:{port} with RPyC {rpyc.__version__}...")
try:
    c = rpyc.connect(host, port)
    print("Connected!")
    print(c.root)
    print("MT5:", c.root.get_mt5())
    print("Version:", c.root.version())
except Exception as e:
    print("Error:", e)
