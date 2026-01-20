"""
Web Dashboard
Bottle-based web server to display trading data via browser.
"""
import os
import json
import bottle
from bottle import route, run, static_file, template
from execution.mt5_bridge import MT5Bridge
import pandas as pd
import threading
import time

# Dashboard State
class WebDashboard:
    def __init__(self, bridge: MT5Bridge, symbols: list):
        self.bridge = bridge
        self.symbols = symbols
        self.data_cache = {
            'account': {},
            'ohlcv': {}
        }
        self.running = False
        
    def start_background_updater(self, interval=2.0):
        self.running = True
        t = threading.Thread(target=self._update_loop, args=(interval,), daemon=True)
        t.start()
        
    def _update_loop(self, interval):
        print("Starting background data updater...")
        while self.running:
            try:
                # Update Account Info
                # Check connection
                if not self.bridge.connected:
                    self.bridge.connect()
                
                acc = self.bridge.get_account_info()
                if acc:
                    self.data_cache['account'] = acc
                
                # Update OHLCV for symbols
                for sym in self.symbols:
                    df = self.bridge.get_ohlcv(sym, timeframe='M15', count=100)
                    if df is not None:
                        # lightweight-charts format: time (unix or string), open, high, low, close
                        # df has 'time' index or column. get_ohlcv returns DataFrame with datetime index
                        
                        # Convert to list of dicts
                        data = []
                        for idx, row in df.iterrows():
                            # idx is datetime if set_index was called
                            t = idx.timestamp() if isinstance(idx, pd.Timestamp) else row['time'].timestamp()
                            data.append({
                                'time': int(t),
                                'open': row['open'],
                                'high': row['high'],
                                'low': row['low'],
                                'close': row['close'],
                            })
                        self.data_cache['ohlcv'][sym] = data
                        
            except Exception as e:
                print(f"Updater error: {e}")
                
            time.sleep(interval)

    def run_server(self, host='0.0.0.0', port=8080):
        # Setup routes
        
        @route('/')
        def index():
            return template('visualization/templates/index.html', symbols=json.dumps(self.symbols))
            
        @route('/api/data')
        def get_data():
            response.content_type = 'application/json'
            return json.dumps(self.data_cache)
            
        print(f"Starting Web Dashboard on http://{host}:{port}")
        run(host=host, port=port, quiet=True)

# Global router needs access to 'response' from bottle
from bottle import response
