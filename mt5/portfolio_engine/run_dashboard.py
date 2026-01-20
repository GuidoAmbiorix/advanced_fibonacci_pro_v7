"""
Run Dashboard
Entry point for launching the portfolio dashboard.
"""
import argparse
import asyncio
import sys

# Add project root to path
# sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from execution.mt5_bridge import MT5Bridge

def main():
    parser = argparse.ArgumentParser(description='Run Portfolio Dashboard')
    parser.add_argument('--symbols', type=str, nargs='+', default=['XAUUSD', 'EURUSD'],
                      help='Symbols to display')
    parser.add_argument('--layout', type=str, default='2x2',
                      help='Chart layout (e.g. 2x2, 3x1)')
    parser.add_argument('--web', action='store_true',
                      help='Run in Web-only mode (bypasses local GUI dependencies)')
    parser.add_argument('--port', type=int, default=8080,
                      help='Port for Web Dashboard')
    
    args = parser.parse_args()
    
    print(f"Starting dashboard for: {args.symbols}")
    
    # Initialize Bridge (supports RPyC auto-detection)
    bridge = MT5Bridge()
    if not bridge.connect():
        print("Failed to connect to MT5 (Local or Remote). Continuing anyway for demo...")
        # In a real scenario, we might want to exit, but for dev we let it run
    
    if args.web:
        print("Launching Web Dashboard...")
        try:
            from visualization.web_dashboard import WebDashboard
            dashboard = WebDashboard(bridge, args.symbols)
            dashboard.start_background_updater()
            dashboard.run_server(port=args.port)
        except ImportError as e:
            print(f"Failed to load Web Dashboard: {e}")
            sys.exit(1)
        except Exception as e:
            print(f"Web Dashboard Error: {e}")
            sys.exit(1)
            
    else:
        # Legacy GUI Mode (Windows Local)
        try:
            from visualization.dashboard import Dashboard
            
            dashboard = Dashboard(args.symbols, args.layout)
            
            # Simple update loop for GUI
            # Note: This is simplified. The original code had specific async logic.
            # Ideally we refactor Dashboard to accept the bridge too, but leaving as is for compatibility if dependencies exist.
            
            async def update_data():
                data = {'ohlcv': {}}
                for sym in args.symbols:
                    df = bridge.get_ohlcv(sym, count=100)
                    if df is not None:
                        data['ohlcv'][sym] = df
                        
                acc = bridge.get_account_info()
                if acc:
                    data['metrics'] = {
                        'equity': acc.get('equity', 0),
                        'dd': 0.0, # Calculation needed
                        'pf': 0.0,
                        'positions': len(bridge.get_positions())
                    }
                return data

            # Run dashboard
            loop = asyncio.get_event_loop()
            loop.run_until_complete(dashboard.run_live(update_data))
            
        except ImportError as e:
             print(f"GUI dependencies missing ({e}). Try running with --web")
             sys.exit(1)
        except Exception as e:
             print(f"GUI Error: {e}")
             sys.exit(1)

if __name__ == '__main__':
    main()
