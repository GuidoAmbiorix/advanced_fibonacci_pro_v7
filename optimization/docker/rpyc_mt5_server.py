#!/usr/bin/env python3
"""
RPyC Server para MT5 Strategy Tester
Ejecuta dentro del contenedor Docker con Wine
"""
import rpyc
from rpyc.utils.server import ThreadedServer
import subprocess
import os
import time
import configparser
import shutil
import re
import json

# Paths dentro del contenedor
MT5_PATH = "/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
MT5_DATA_PATH = "/root/.wine/drive_c/Program Files/MetaTrader 5"
REPORTS_DIR = "/tmp/mt5_reports"

class MT5TesterService(rpyc.Service):
    """Servicio RPyC que expone funciones de MT5 Strategy Tester"""
    
    def on_connect(self, conn):
        print(f"🔗 Client connected from {conn._channel.stream.sock.getpeername()}")
        
    def on_disconnect(self, conn):
        print("🔌 Client disconnected")
    
    def exposed_ping(self):
        """Test de conectividad"""
        return "pong"
    
    def exposed_get_status(self):
        """Retorna estado del servidor"""
        mt5_exists = os.path.exists(MT5_PATH)
        return {
            'mt5_installed': mt5_exists,
            'mt5_path': MT5_PATH,
            'reports_dir': REPORTS_DIR,
            'ready': mt5_exists
        }
    
    def exposed_run_backtest(self, config_dict):
        """
        Ejecuta backtest usando CLI de MT5
        
        config_dict debe contener:
            - ea_name: nombre del EA (ej: "MyBot.ex5")
            - symbol: símbolo (ej: "XAUUSDm")
            - timeframe: timeframe (ej: "M15" o "PERIOD_M15")
            - date_from: fecha inicio (ej: "2025.01.01")
            - date_to: fecha fin (ej: "2025.12.31")
            - deposit: depósito inicial
            - leverage: apalancamiento
            - parameters: dict con parámetros del EA
            - login: cuenta MT5
            - password: contraseña
            - server: servidor broker
        """
        print(f"📊 Starting backtest: {config_dict.get('ea_name', 'Unknown')}")
        
        os.makedirs(REPORTS_DIR, exist_ok=True)
        
        timestamp = int(time.time() * 1000)
        ini_path = f"{REPORTS_DIR}/config_{timestamp}.ini"
        report_path = f"{REPORTS_DIR}/report_{timestamp}.htm"
        set_filename = f"params_{timestamp}.set"
        set_path = f"{REPORTS_DIR}/{set_filename}"
        
        # Extraer datos
        ea_name = config_dict.get('ea_name', '')
        symbol = config_dict.get('symbol', 'EURUSD')
        timeframe = config_dict.get('timeframe', 'M15')
        date_from = config_dict.get('date_from', '2025.01.01')
        date_to = config_dict.get('date_to', '2025.12.31')
        deposit = config_dict.get('deposit', 10000)
        leverage = config_dict.get('leverage', 500)
        parameters = config_dict.get('parameters', {})
        login = config_dict.get('login', '')
        password = config_dict.get('password', '')
        server = config_dict.get('server', '')
        
        # Convertir timeframe
        if timeframe.startswith('PERIOD_'):
            timeframe = timeframe.replace('PERIOD_', '')
        
        # Asegurar formato .ex5
        if ea_name.endswith('.mq5'):
            ea_name = ea_name.replace('.mq5', '.ex5')
        
        # 1. Crear archivo .ini
        config = configparser.ConfigParser()
        config.optionxform = str  # Mantener case
        
        config['Common'] = {
            'Login': str(login),
            'Password': password,
            'Server': server
        }
        
        config['Tester'] = {
            'Expert': f"Experts\\{ea_name}",
            'Symbol': symbol,
            'Period': timeframe,
            'Optimization': '0',
            'Model': '0',  # Every tick
            'Deposit': str(deposit),
            'Currency': 'USD',
            'Leverage': f"1:{leverage}",
            'FromDate': date_from,
            'ToDate': date_to,
            'Report': report_path,
            'ReplaceReport': '1',
            'ShutdownTerminal': '1',
            'ExpertParameters': set_filename
        }
        
        with open(ini_path, 'w') as f:
            config.write(f)
        
        print(f"✅ Config written: {ini_path}")
        
        # 2. Crear archivo .set con parámetros
        with open(set_path, 'w', encoding='utf-16-le') as f:
            f.write('\ufeff')  # BOM
            for k, v in parameters.items():
                if v is True:
                    val = "true"
                elif v is False:
                    val = "false"
                else:
                    val = str(v)
                f.write(f"{k}={val}\n")
        
        print(f"✅ Parameters written: {set_path}")
        
        # 3. Copiar .set a carpeta Presets de MT5
        presets_dir = os.path.join(MT5_DATA_PATH, "MQL5", "Presets")
        os.makedirs(presets_dir, exist_ok=True)
        shutil.copy(set_path, os.path.join(presets_dir, set_filename))
        
        # 4. Ejecutar MT5 con xvfb-run
        cmd = f'xvfb-run -a wine "{MT5_PATH}" /config:"{ini_path}"'
        print(f"🚀 Executing: {cmd}")
        
        try:
            # Timeout de 10 minutos
            result = subprocess.run(
                cmd, 
                shell=True, 
                timeout=600,
                capture_output=True,
                text=True,
                env={**os.environ, 'DISPLAY': ':99'}
            )
            print(f"MT5 exit code: {result.returncode}")
            if result.stderr:
                print(f"MT5 stderr: {result.stderr[:500]}")
        except subprocess.TimeoutExpired:
            print("❌ Backtest timeout (10 min)")
            return {'error': 'Backtest timeout', 'profit_factor': 0, 'max_drawdown': 100, 'win_rate': 0}
        except Exception as e:
            print(f"❌ Execution error: {e}")
            return {'error': str(e), 'profit_factor': 0, 'max_drawdown': 100, 'win_rate': 0}
        
        # 5. Esperar a que se genere el reporte
        time.sleep(5)
        
        # 6. Parsear reporte
        if os.path.exists(report_path):
            print(f"✅ Report found: {report_path}")
            return self._parse_report(report_path)
        else:
            print(f"❌ Report not found: {report_path}")
            # Buscar en ubicación alternativa
            alt_reports = [f for f in os.listdir(REPORTS_DIR) if f.endswith('.htm')]
            if alt_reports:
                alt_path = os.path.join(REPORTS_DIR, sorted(alt_reports)[-1])
                print(f"📊 Using alternative report: {alt_path}")
                return self._parse_report(alt_path)
            
            return {'error': 'Report not generated', 'profit_factor': 0, 'max_drawdown': 100, 'win_rate': 0}
    
    def _parse_report(self, html_path):
        """Parsea reporte HTML de MT5 y extrae métricas"""
        result = {
            'total_net_profit': 0.0,
            'profit_factor': 0.0,
            'max_drawdown': 100.0,
            'total_trades': 0,
            'win_rate': 0.0,
            'sharpe_ratio': 0.0,
            'recovery_factor': 0.0
        }
        
        try:
            # Intentar diferentes encodings
            html = None
            for encoding in ['utf-8', 'utf-16', 'latin-1', 'cp1252']:
                try:
                    with open(html_path, 'r', encoding=encoding) as f:
                        html = f.read()
                    break
                except:
                    continue
            
            if not html:
                return result
            
            # Patrones para extraer métricas
            patterns = {
                'total_net_profit': r'Total Net Profit</td>\s*<td[^>]*>([^<]+)',
                'profit_factor': r'Profit Factor</td>\s*<td[^>]*>([^<]+)',
                'max_drawdown': r'(?:Maximal Drawdown|Max\. Drawdown)</td>\s*<td[^>]*>([^<]+)',
                'total_trades': r'Total Trades</td>\s*<td[^>]*>([^<]+)',
                'win_rate': r'(?:Win Rate|Profit Trades \(%\))</td>\s*<td[^>]*>([^<]+)',
                'sharpe_ratio': r'Sharpe Ratio</td>\s*<td[^>]*>([^<]+)',
                'recovery_factor': r'Recovery Factor</td>\s*<td[^>]*>([^<]+)'
            }
            
            for key, pattern in patterns.items():
                match = re.search(pattern, html, re.IGNORECASE | re.DOTALL)
                if match:
                    val_str = match.group(1).strip()
                    # Limpiar valor
                    val_str = re.sub(r'[^\d.\-]', '', val_str.split('%')[0].split('(')[0])
                    try:
                        result[key] = float(val_str) if val_str else 0.0
                    except ValueError:
                        pass
            
            print(f"📈 Parsed results: PF={result['profit_factor']}, DD={result['max_drawdown']}%, WR={result['win_rate']}%")
            return result
            
        except Exception as e:
            print(f"❌ Parse error: {e}")
            return result


def main():
    print("=" * 50)
    print("🚀 MT5 RPyC Server Starting...")
    print(f"   Port: 18812")
    print(f"   MT5 Path: {MT5_PATH}")
    print(f"   MT5 Installed: {os.path.exists(MT5_PATH)}")
    print("=" * 50)
    
    server = ThreadedServer(
        MT5TesterService, 
        port=18812,
        protocol_config={
            'allow_public_attrs': True,
            'allow_pickle': True,
            'sync_request_timeout': 660  # 11 min timeout
        }
    )
    
    print("✅ Server ready, waiting for connections...")
    server.start()


if __name__ == "__main__":
    main()
