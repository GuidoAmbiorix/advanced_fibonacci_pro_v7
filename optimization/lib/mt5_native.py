"""
MT5 Native Windows Interface
Reemplaza completamente Docker/Wine con ejecución nativa de terminal64.exe
"""
import subprocess
import os
import tempfile
import time
import re
from pathlib import Path
from typing import Dict, Optional, Callable
from xml.etree import ElementTree as ET
from html.parser import HTMLParser


class MT5ReportParser(HTMLParser):
    """Parser para reportes HTML de MT5"""
    
    def __init__(self):
        super().__init__()
        self.metrics = {}
        self.current_tag = None
        self.current_data = []
        self.in_table = False
        
    def handle_starttag(self, tag, attrs):
        if tag == 'table':
            self.in_table = True
        self.current_tag = tag
        
    def handle_data(self, data):
        if self.in_table and data.strip():
            self.current_data.append(data.strip())
            
            # Buscar Profit Factor
            if 'Profit Factor' in data or 'profit factor' in data.lower():
                try:
                    # El siguiente dato debería ser el valor
                    pass
                except:
                    pass
    
    def handle_endtag(self, tag):
        if tag == 'table':
            self.in_table = False
        self.current_tag = None


class MT5Windows:
    """Interfaz nativa para MT5 en Windows"""
    
    def __init__(self, mt5_path: Optional[str] = None):
        """
        Inicializa MT5 interface.
        
        Args:
            mt5_path: Path to MT5 installation (auto-detect if None)
        """
        if mt5_path:
            self.mt5_path = Path(mt5_path)
        else:
            self.mt5_path = self._find_mt5_installation()
        
        self.terminal_exe = self.mt5_path / "terminal64.exe"
        
        if not self.terminal_exe.exists():
            raise FileNotFoundError(
                f"MT5 terminal64.exe not found at {self.terminal_exe}"
            )
        
        print(f"✅ MT5 found at: {self.mt5_path}")
    
    def _find_mt5_installation(self) -> Path:
        """Detecta instalación MT5 automáticamente"""
        common_paths = [
            Path("C:/Program Files/MetaTrader 5"),
            Path("C:/Program Files (x86)/MetaTrader 5"),
            Path.home() / "AppData/Roaming/MetaQuotes/Terminal",
        ]
        
        for base_path in common_paths:
            if base_path.exists():
                # Buscar terminal64.exe recursivamente
                for root, dirs, files in os.walk(base_path):
                    if "terminal64.exe" in files:
                        return Path(root)
        
        raise FileNotFoundError(
            "MT5 installation not found! Please install MT5 or specify path manually."
        )
    
    def run_backtest(
        self,
        ea_path: str,
        symbol: str,
        timeframe: str,
        date_from: str,
        date_to: str,
        deposit: float = 10000,
        parameters: Optional[Dict] = None,
        progress_callback: Optional[Callable[[str, int], None]] = None
    ) -> Dict:
        """
        Ejecuta un backtest en MT5 y retorna los resultados.
        
        Args:
            ea_path: Path al EA (.ex5 file)
            symbol: Symbol (e.g., "XAUUSD")
            timeframe: Timeframe (e.g., "H1", "D1")
            date_from: Fecha inicio (formato: "2024.01.01")
            date_to: Fecha fin (formato: "2024.12.31")
            deposit: Depósito inicial
            parameters: Dict de parámetros del EA
            progress_callback: Callback para updates (mensaje, porcentaje)
        
        Returns:
            Dict con métricas del backtest
        """
        if parameters is None:
            parameters = {}
        
        if progress_callback:
            progress_callback("Preparando backtest...", 5)
        
        # 1. Crear archivos temporales
        ini_file = tempfile.NamedTemporaryFile(
            mode='w', suffix='.ini', delete=False, encoding='utf-8'
        )
        report_file = tempfile.NamedTemporaryFile(
            suffix='.htm', delete=False
        )
        
        ini_path = ini_file.name
        report_path = report_file.name
        
        ini_file.close()
        report_file.close()
        
        try:
            # 2. Crear tester.ini
            if progress_callback:
                progress_callback("Creando configuración...", 10)
            
            self._create_tester_ini(
                ini_path, report_path, ea_path, symbol, timeframe,
                date_from, date_to, deposit, parameters
            )
            
            # 3. Ejecutar MT5
            if progress_callback:
                progress_callback("Ejecutando MT5...", 20)
            
            result = self._execute_mt5(ini_path, progress_callback)
            
            # 4. Esperar reporte
            if progress_callback:
                progress_callback("Esperando reporte...", 80)
            
            self._wait_for_report(report_path, timeout=120)
            
            # 5. Parse reporte
            if progress_callback:
                progress_callback("Parseando resultados...", 90)
            
            metrics = self._parse_report(report_path)
            
            if progress_callback:
                progress_callback("Completado", 100)
            
            return metrics
            
        finally:
            # Cleanup
            try:
                os.unlink(ini_path)
            except:
                pass
            try:
                os.unlink(report_path)
            except:
                pass
    
    def _create_tester_ini(
        self,
        ini_path: str,
        report_path: str,
        ea_path: str,
        symbol: str,
        timeframe: str,
        date_from: str,
        date_to: str,
        deposit: float,
        parameters: Dict
    ):
        """Crea archivo tester.ini para MT5"""
        
        # Extract just the filename - MT5 looks in its own Experts folder
        ea_filename = Path(ea_path).name
        
        # Convertir timeframe a número
        tf_map = {
            "M1": "1", "M5": "5", "M15": "15", "M30": "30",
            "H1": "60", "H4": "240", "D1": "1440", "W1": "10080", "MN1": "43200"
        }
        period = tf_map.get(timeframe.upper(), "60")
        
        ini_content = f"""[Tester]
Expert={ea_filename}
Symbol={symbol}
Period={period}
Optimization=0
Model=1
Visual=0
FromDate={date_from}
ToDate={date_to}
ForwardMode=0
Deposit={deposit}
Currency=USD
Leverage=500
ExecutionMode=0
Report={report_path}
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
"""
        
        # Agregar parámetros del EA
        for key, value in parameters.items():
            if isinstance(value, bool):
                val_str = "true" if value else "false"
            elif isinstance(value, float):
                val_str = f"{value:.8f}".rstrip('0').rstrip('.')
            else:
                val_str = str(value)
            
            ini_content += f"{key}={val_str}\n"
        
        # Escribir archivo
        with open(ini_path, 'w', encoding='utf-8') as f:
            f.write(ini_content)
        
        print(f"📝 Tester.ini created: {ini_path}")
        print(f"📄 INI Contents:")
        print("=" * 60)
        print(ini_content[:500])  # Show first 500 chars
        print("=" * 60)
    
    def _execute_mt5(
        self,
        ini_path: str,
        progress_callback: Optional[Callable[[str, int], None]] = None
    ) -> subprocess.CompletedProcess:
        """Ejecuta MT5 terminal con configuración"""
        
        cmd = [
            str(self.terminal_exe),
            f"/config:{ini_path}",
            "/portable"
        ]
        
        print(f"🚀 Executing: {' '.join(cmd)}")
        
        # Ejecutar MT5
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600,  # 10 minutos max
            cwd=str(self.mt5_path)
        )
        
        if result.returncode != 0:
            print(f"⚠️ MT5 exited with code: {result.returncode}")
            if result.stderr:
                print(f"STDERR: {result.stderr[:500]}")
        
        return result
    
    def _wait_for_report(self, report_path: str, timeout: int = 120):
        """Espera a que se genere el reporte"""
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            if os.path.exists(report_path):
                # Verificar que tiene contenido
                try:
                    size = os.path.getsize(report_path)
                    if size > 100:  # Mínimo 100 bytes
                        time.sleep(1)  # Esperar un poco más para asegurar escritura
                        print(f"✅ Report found: {report_path} ({size} bytes)")
                        return
                except:
                    pass
            
            time.sleep(0.5)
        
        print(f"⚠️ Report not found after {timeout}s: {report_path}")
    
    def _parse_report(self, report_path: str) -> Dict:
        """Parse reporte HTML/HTM de MT5"""
        
        if not os.path.exists(report_path):
            return {
                "success": False,
                "profit_factor": 0.0,
                "error": "Report file not found"
            }
        
        try:
            with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            metrics = {
                "success": True,
                "profit_factor": 0.0,
                "total_net_profit": 0.0,
                "gross_profit": 0.0,
                "gross_loss": 0.0,
                "total_trades": 0,
                "win_rate": 0.0,
                "max_drawdown": 0.0,
            }
            
            # Buscar métricas con regex
            patterns = {
                "profit_factor": r"Profit\s*Factor[:\s]+([0-9.]+)",
                "total_net_profit": r"Total\s*Net\s*Profit[:\s]+([0-9.-]+)",
                "gross_profit": r"Gross\s*Profit[:\s]+([0-9.-]+)",
                "gross_loss": r"Gross\s*Loss[:\s]+([0-9.-]+)",
                "total_trades": r"Total\s*Trades[:\s]+([0-9]+)",
                "max_drawdown": r"Maximal\s*Drawdown[:\s]+([0-9.]+)",
            }
            
            for key, pattern in patterns.items():
                match = re.search(pattern, content, re.IGNORECASE)
                if match:
                    try:
                        value = match.group(1).strip()
                        if key == "total_trades":
                            metrics[key] = int(value)
                        else:
                            metrics[key] = float(value)
                    except ValueError:
                        pass
            
            # Calcular win rate si tenemos datos
            if "profit trades" in content.lower():
                win_match = re.search(
                    r"Profit\s*Trades[:\s]+([0-9]+)\s*\(([0-9.]+)%\)",
                    content,
                    re.IGNORECASE
                )
                if win_match:
                    try:
                        metrics["win_rate"] = float(win_match.group(2))
                    except:
                        pass
            
            print(f"📊 Parsed metrics: PF={metrics['profit_factor']:.2f}, Trades={metrics['total_trades']}")
            
            return metrics
            
        except Exception as e:
            print(f"❌ Error parsing report: {e}")
            return {
                "success": False,
                "profit_factor": 0.0,
                "error": str(e)
            }


# Global instance (singleton)
_mt5_instance: Optional[MT5Windows] = None


def get_mt5_instance(mt5_path: Optional[str] = None) -> MT5Windows:
    """Obtiene instancia global de MT5Windows"""
    global _mt5_instance
    
    if _mt5_instance is None:
        _mt5_instance = MT5Windows(mt5_path)
    
    return _mt5_instance


# Compatibility function for optimizer_core.py
def run_mt5_test(
    ini_path=None,
    report_path=None,
    ea_path=None,
    symbol=None,
    timeframe=None,
    date_from=None,
    date_to=None,
    deposit=None,
    params=None
):
    """
    Wrapper function for compatibility with existing optimizer_core.py
    Now uses native Windows MT5 instead of Docker API
    """
    mt5 = get_mt5_instance()
    
    result = mt5.run_backtest(
        ea_path=ea_path,
        symbol=symbol,
        timeframe=timeframe,
        date_from=date_from,
        date_to=date_to,
        deposit=deposit or 10000,
        parameters=params or {}
    )
    
    return result.get("success", False)


def get_last_profit_factor():
    """Returns last profit factor (for compatibility)"""
    # This will be updated by run_mt5_test
    global _last_profit_factor
    return getattr(get_last_profit_factor, '_pf', 0.0)


_last_profit_factor = 0.0
