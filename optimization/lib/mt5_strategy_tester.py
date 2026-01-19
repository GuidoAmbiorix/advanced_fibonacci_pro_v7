import os
import subprocess
import configparser
import time
import shutil
import sys
from datetime import datetime

# ============================================================
# CONFIGURATION: Choose execution mode
# ============================================================
USE_DOCKER_RPYC = True  # Set to True to use Docker container, False for local Windows MT5

# MT5 Account Credentials (used for both modes)
MT5_LOGIN = '198035354'
MT5_PASSWORD = 'Motivo@1'
MT5_SERVER = 'Exness-MT5Trial11'

# Docker RPyC Settings
RPYC_HOST = 'localhost'
RPYC_PORT = 18812
# ============================================================

class MT5StrategyTester:
    def __init__(self, terminal_path=r"C:\Program Files\MetaTrader 5\terminal64.exe", 
                 data_path=r"C:\Users\Ing Guido\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"):
        self.terminal_exe = terminal_path
        self.data_path = data_path
        self.reports_dir = os.path.join(os.path.dirname(__file__), "..", "reports")
        os.makedirs(self.reports_dir, exist_ok=True)
        
        # RPyC client (lazy init)
        self._rpyc_client = None
        
    def run_backtest(self, ea_name, symbol, timeframe, date_from, date_to, deposit, leverage, parameters):
        """
        Runs MT5 Strategy Tester
        Uses Docker RPyC if USE_DOCKER_RPYC=True, otherwise local Windows MT5
        """
        if USE_DOCKER_RPYC:
            return self._run_backtest_rpyc(ea_name, symbol, timeframe, date_from, date_to, deposit, leverage, parameters)
        else:
            return self._run_backtest_local(ea_name, symbol, timeframe, date_from, date_to, deposit, leverage, parameters)
    
    def _run_backtest_rpyc(self, ea_name, symbol, timeframe, date_from, date_to, deposit, leverage, parameters):
        """
        Run backtest using Python-based engine (via RPyC for data)
        Much faster than Strategy Tester!
        """
        try:
            from .python_backtester import get_backtester
            
            backtester = get_backtester()
            if not backtester.connected:
                 if not backtester.connect():
                    print("❌ Failed to connect to MT5 RPyC server (Python Backtester)")
                    print("   Make sure Docker container is running: docker-compose -f docker-compose.rpyc.yml up -d")
                    return {}
            
            print(f"🚀 Running Python Backtest on {symbol} {timeframe} ({date_from}-{date_to})...")
            
            result = backtester.run_backtest(
                symbol=symbol,
                timeframe=timeframe,
                date_from=date_from,
                date_to=date_to,
                deposit=float(deposit),
                leverage=int(leverage),
                parameters=parameters
            )
            
            # Map Python Backtester results to expected format
            # Our Python backtester returns: {'total_net_profit', 'profit_factor', 'max_drawdown', 'win_rate', ...}
            # MT5 reports return similar keys, but let's ensure consistency
            
            if 'error' in result:
                return {'profit_factor': 0, 'max_drawdown': 100, 'win_rate': 0}
                
            return {
                'profit_factor': result.get('profit_factor', 0),
                'max_drawdown': result.get('max_drawdown', 0),
                'win_rate': result.get('win_rate', 0),
                'total_net_profit': result.get('total_net_profit', 0),
                'total_trades': result.get('total_trades', 0)
            }
            
        except ImportError as e:
            print(f"❌ Python Backtester Import Error: {e}")
            return {}
        except Exception as e:
            print(f"❌ Backtest Error: {e}")
            import traceback
            traceback.print_exc()
            return {}
    
    def _run_backtest_local(self, ea_name, symbol, timeframe, date_from, date_to, deposit, leverage, parameters):
        """Run backtest using local Windows MT5 (original method)"""
        # 0. PRE-CHECK: Enable symbol in Market Watch via API to ensure it appears in Tester
        try:
            import MetaTrader5 as mt5
            # We must initialize with the path to the specific terminal we are automating
            if mt5.initialize(path=self.terminal_exe):
                if not mt5.symbol_select(symbol, True):
                    print(f"⚠️ Failed to enable {symbol} in Market Watch (API).")
                else:
                    print(f"✅ Enabled {symbol} in Market Watch (API).")
                mt5.shutdown()
            else:
                print(f"⚠️ MT5 API Initialization failed: {mt5.last_error()}")
        except Exception as e:
            print(f"⚠️ MT5 API Warning: {e}")

        # 1. Prepare Paths
        # ea_name should be relative to Experts folder, e.g., "XAU_Pro_Agent_Gen_v1.mq5"
        if os.path.isabs(ea_name):
            ea_name = os.path.basename(ea_name)
            
        report_name = f"report_{int(time.time()*1000)}"
        report_path = os.path.join(self.reports_dir, report_name + ".htm")  # HTML format
        ini_path = os.path.join(self.reports_dir, f"config_{int(time.time()*1000)}.ini")
        
        # 2. Convert Timeframe string to MT5 string format
        # MT5 INI expects Period=M15, H1, etc.
        if timeframe.startswith("PERIOD_"):
            timeframe = timeframe.replace("PERIOD_", "")
        
        # 3. Load Existing Config (To preserve Saved Passwords/Login)
        common_ini_path = os.path.join(self.data_path, "config", "common.ini")
        
        config = configparser.ConfigParser()
        config.optionxform = str # Preserve case sensitivity
        
        # Try to read credentials from actual common.ini
        if os.path.exists(common_ini_path):
            try:
                # MT5 ini files are often UTF-16
                config.read(common_ini_path, encoding='utf-16')
            except:
                try:
                    config.read(common_ini_path) # Try default encoding
                except:
                    print("⚠️ Could not read common.ini, starting fresh.")

        # Ensure Startup section uses the CORRECT Hedging Login (User ID)
        if 'Startup' not in config:
            config['Startup'] = {}
            
        # Hard-force credentials for automated login
        config['Startup']['Login'] = '198035354' 
        config['Startup']['Server'] = 'Exness-MT5Trial11'
        config['Startup']['Password'] = 'Motivo@1'
        
        # 4. Configure Tester
        # IMPORTANT: Tester needs .ex5 file, not .mq5
        ea_name_ex5 = ea_name.replace(".mq5", ".ex5") if ea_name.endswith(".mq5") else ea_name
        
        # First, generate set filename for later use
        set_filename = f"optuna_trial_{int(time.time()*1000)}.set"
        
        config['Common'] = {
            'Login': '198035354',
            'Password': 'Motivo@1',
            'Server': 'Exness-MT5Trial11',
            'CertPassword': ''
        }

        config['Tester'] = {
            'Expert': f"Experts\\{ea_name_ex5}",
            'Symbol': symbol,
            'Period': timeframe,
            'Login': '198035354', 
            'Optimization': '0',
            'Model': '0',
            'Deposit': str(deposit),
            'Currency': 'USD',
            'Leverage': f"1:{leverage}",
            'FromDate': date_from, 
            'ToDate': date_to,
            'Report': report_path,
            'ReplaceReport': '1',
            'ShutdownTerminal': '0',
            'ExpertParameters': set_filename
        }
        
        # 4. Add Parameters
        # ... (Removed config['TesterInputs'] loop as it's not needed for .set file approach) ...

        # Write INI
        with open(ini_path, 'w') as configfile:
            config.write(configfile)
        
        # Also create .set file with parameters in MT5 Presets folder
        presets_dir = os.path.join(self.data_path, "MQL5", "Presets")
        os.makedirs(presets_dir, exist_ok=True)
        set_path = os.path.join(presets_dir, set_filename)
        
        with open(set_path, 'w', encoding='utf-16-le') as setfile:
            setfile.write('\ufeff')
            for k, v in parameters.items():
                val = "true" if v is True else "false" if v is False else str(v)
                # Simple Key=Value for Single Run
                setfile.write(f"{k}={val}\n")
        
        print(f"✅ Config written: {ini_path}")
        print(f"✅ Parameters written: {set_path}")
        
        # ⚠️ CRITICAL FIX: Modify common.ini DIRECTLY
        # ... (Same common.ini modification code) ...
        subprocess.run(["taskkill", "/f", "/im", "terminal64.exe"], stderr=subprocess.DEVNULL)
        time.sleep(1)
        
        try:
            with open(common_ini_path, 'r', encoding='utf-16') as f:
                common_content = f.read()
            import re
            common_content = re.sub(r'(Login=)\d+', r'\g<1>198035354', common_content)
            common_content = re.sub(r'(Server=)[^\r\n]+', r'\g<1>Exness-MT5Trial11', common_content)
            if 'Password=' in common_content:
                common_content = re.sub(r'(Password=)[^\r\n]+', r'\g<1>Motivo@1', common_content)
            else:
                common_content = re.sub(r'(Login=198035354)', r'\g<1>\r\nPassword=Motivo@1', common_content)
            with open(common_ini_path, 'w', encoding='utf-16') as f:
                f.write(common_content)
            print("✅ Forced credentials in common.ini")
        except Exception as e:
            print(f"⚠️ Could not modify common.ini: {e}")
            
        # 5. EXECUTE VIA GUI WRAPPER
        try:
            # Add current dir to path to find the module if needed
            sys.path.append(os.path.dirname(__file__))
            from mt5_gui_wrapper import MT5GUIWrapper
            
            gui = MT5GUIWrapper(self.terminal_exe)
            
            # Launch and Automate
            if gui.launch_and_wait(ini_path):
                gui.ensure_strategy_tester_open()
                gui.start_backtest_and_wait()
            else:
                print("❌ GUI Launch failed")
                return {}
        except ImportError:
            print("⚠️ GUI Wrapper not found/pywinauto missing. Fallback to CLI.")
            cmd = [self.terminal_exe, f"/config:{ini_path}"]
            subprocess.Popen(cmd)
        except Exception as e:
            print(f"❌ Automation Error: {e}")
            
        print(f"⏳ Waiting for report generation...")
            
        # Wait for report to be generated (poll for file)
        max_wait = 300  # 5 minutes max
        waited = 0
        
        # MT5 often ignores custom report paths and saves to default location
        # Check both locations
        default_report_dir = os.path.join(self.data_path, "tester", "reports")
        default_report_path = None
        
        while waited < max_wait:
            # Check custom path
            if os.path.exists(report_path):
                time.sleep(2)
                break
            
            # Check MT5 default location (often the real location)
            if os.path.exists(default_report_dir):
                # Find most recent .htm file
                reports = [f for f in os.listdir(default_report_dir) if f.endswith('.htm')]
                if reports:
                    reports.sort(key=lambda x: os.path.getmtime(os.path.join(default_report_dir, x)), reverse=True)
                    default_report_path = os.path.join(default_report_dir, reports[0])
                    print(f"📊 Found report in default location: {default_report_path}")
                    # Copy to expected location
                    shutil.copy(default_report_path, report_path)
                    break
            
            time.sleep(1)
            waited += 1
            
        if not os.path.exists(report_path):
            print(f"❌ Report not generated after {max_wait}s")
            return {}
                


        # 6. Parse Result
        if os.path.exists(report_path):
            return self.parse_report(report_path)
        else:
            print(f"❌ Report not found: {report_path}")
            # Check logs maybe?
            return {}
            
    def parse_report(self, html_path):
        """Parses MT5 HTML Report for metrics using regex"""
        try:
            import re
            
            with open(html_path, 'r', encoding='utf-8') as f:
                html = f.read()
            
            # MT5 HTML has tables with specific patterns
            # Example: <td>Total net profit</td><td align="right">1234.56</td>
            
            def extract_value(pattern, default=0.0):
                match = re.search(pattern, html, re.IGNORECASE)
                if match:
                    try:
                        return float(match.group(1).replace(',', '').replace(' ', ''))
                    except:
                        return default
                return default
            
            res = {}
            
            # Extract key metrics (adjust patterns based on actual MT5 HTML structure)
            res['total_net_profit'] = extract_value(r'Total net profit.*?>([\d\.\-\,]+)', 0)
            res['gross_profit'] = extract_value(r'Gross profit.*?>([\d\.\-\,]+)', 0)
            res['gross_loss'] = extract_value(r'Gross loss.*?>([\d\.\-\,]+)', 0)
            res['profit_factor'] = extract_value(r'Profit factor.*?>([\d\.\-\,]+)', 0)
            res['total_trades'] = int(extract_value(r'Total trades.*?>([\d\.\-\,]+)', 0))
            
            # Drawdown can be in % or absolute
            dd_pct = extract_value(r'Maximal drawdown.*?\(([\d\.\-\,]+)%\)', 0)
            if dd_pct == 0:
                dd_pct = extract_value(r'Drawdown.*?>([\d\.\-\,]+)', 0)
            res['max_drawdown'] = dd_pct
            
            # Win Rate calculation
            wins = int(extract_value(r'Won.*?trades.*?>([\d\.\-\,]+)', 0))
            trades = res['total_trades']
            res['win_rate'] = (wins / trades * 100) if trades > 0 else 0
            
            return res
            
        except Exception as e:
            print(f"⚠️ HTML Parse Failed: {e}")
            import traceback
            traceback.print_exc()
            return {}

# Function to get singleton
_tester = None
def get_mt5_tester():
    global _tester
    if _tester is None:
        _tester = MT5StrategyTester()
    return _tester
