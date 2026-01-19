"""
MT5 RPyC Client
Connects to the Docker container running MT5 with Wine

Usage:
    from lib.mt5_rpyc_client import MT5RPyCClient
    
    client = MT5RPyCClient()
    if client.connect():
        result = client.run_backtest(config)
        client.close()
"""
import rpyc


class MT5RPyCClient:
    """Cliente para conectarse al servidor RPyC de MT5 en Docker"""
    
    def __init__(self, host='localhost', port=18812, timeout=660):
        """
        Args:
            host: Host del contenedor Docker (default: localhost)
            port: Puerto del servidor RPyC (default: 18812)
            timeout: Timeout para operaciones en segundos (default: 660 = 11 min)
        """
        self.host = host
        self.port = port
        self.timeout = timeout
        self.conn = None
    
    def connect(self):
        """Conectar al servidor RPyC"""
        try:
            self.conn = rpyc.connect(
                self.host, 
                self.port,
                config={
                    'sync_request_timeout': self.timeout,
                    'allow_public_attrs': True,
                    'allow_pickle': True
                }
            )
            # Test connection
            pong = self.conn.root.ping()
            if pong == "pong":
                print(f"✅ Connected to MT5 RPyC Server at {self.host}:{self.port}")
                return True
            return False
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            return False
    
    def get_status(self):
        """Obtener estado del servidor"""
        if not self.conn:
            if not self.connect():
                return None
        return self.conn.root.get_status()
    
    def run_backtest(self, ea_name, symbol, timeframe, date_from, date_to, 
                    deposit, leverage, parameters, 
                    login='', password='', server=''):
        """
        Ejecutar backtest via RPyC
        
        Args:
            ea_name: Nombre del EA (ej: "MyBot.ex5")
            symbol: Símbolo (ej: "XAUUSDm")
            timeframe: Timeframe (ej: "M15" o "PERIOD_M15")
            date_from: Fecha inicio (ej: "2025.01.01")
            date_to: Fecha fin (ej: "2025.12.31")
            deposit: Depósito inicial
            leverage: Apalancamiento
            parameters: Dict con parámetros del EA
            login: Cuenta MT5
            password: Contraseña MT5
            server: Servidor del broker
        
        Returns:
            dict con resultados del backtest
        """
        if not self.conn:
            if not self.connect():
                return {
                    'error': 'Not connected to RPyC server',
                    'profit_factor': 0.0,
                    'max_drawdown': 100.0,
                    'win_rate': 0.0
                }
        
        config = {
            'ea_name': ea_name,
            'symbol': symbol,
            'timeframe': timeframe,
            'date_from': date_from,
            'date_to': date_to,
            'deposit': deposit,
            'leverage': leverage,
            'parameters': dict(parameters),  # Ensure it's a regular dict
            'login': login,
            'password': password,
            'server': server
        }
        
        try:
            result = self.conn.root.run_backtest(config)
            # Convert netref to regular dict
            return dict(result) if result else {}
        except Exception as e:
            print(f"❌ Backtest error: {e}")
            return {
                'error': str(e),
                'profit_factor': 0.0,
                'max_drawdown': 100.0,
                'win_rate': 0.0
            }
    
    def close(self):
        """Cerrar conexión"""
        if self.conn:
            try:
                self.conn.close()
            except:
                pass
            self.conn = None
            print("🔌 Disconnected from MT5 RPyC Server")


# Singleton instance for reuse
_client_instance = None

def get_client(host='localhost', port=18812):
    """Get or create a shared client instance"""
    global _client_instance
    if _client_instance is None or _client_instance.conn is None:
        _client_instance = MT5RPyCClient(host, port)
        _client_instance.connect()
    return _client_instance
