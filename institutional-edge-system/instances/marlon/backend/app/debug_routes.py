import sys
import os

sys.path.append("/app")

try:
    import unittest.mock
    sys.modules["MetaTrader5"] = unittest.mock.MagicMock()
    
    from app.main import app
    
    real_app = app
    if hasattr(app, "other_asgi_app"):
         real_app = app.other_asgi_app
    
    if hasattr(real_app, "routes"):
        print("=== BEGIN ROUTES ===")
        for route in real_app.routes:
            methods = ", ".join(route.methods) if hasattr(route, "methods") else "None"
            print(f"{route.path} | {methods}")
        print("=== END ROUTES ===")
    else:
        print("Still no .routes attribute found on inner app.")

except Exception as e:
    import traceback
    traceback.print_exc()
