# 📋 Plan: Docker + Wine + RPyC para Automatización MT5

## 🎯 Objetivo
Ejecutar MT5 Strategy Tester de forma completamente automatizada usando Docker, Wine y RPyC para comunicación remota desde Python.

---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                        HOST (Windows/Linux)                      │
│  ┌─────────────────┐                                            │
│  │   Dashboard     │                                            │
│  │   (Streamlit)   │◄────────────────────────────┐              │
│  │                 │                              │              │
│  │   Optuna        │                              │              │
│  └────────┬────────┘                              │              │
│           │                                       │              │
│           │ RPyC Client                   Results │              │
│           ▼                                       │              │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    DOCKER CONTAINER                          ││
│  │  ┌─────────────┐    ┌──────────────┐    ┌────────────────┐  ││
│  │  │   RPyC      │◄──►│   Python     │◄──►│  MetaTrader 5  │  ││
│  │  │   Server    │    │  MT5 API     │    │  (Wine + Xvfb) │  ││
│  │  │  :18812     │    │              │    │                │  ││
│  │  └─────────────┘    └──────────────┘    └────────────────┘  ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## 📦 Componentes

### 1. Docker Container
- **Base**: Ubuntu 22.04 o Debian
- **Wine**: Para ejecutar MT5 (aplicación Windows)
- **Xvfb**: Display virtual (headless, sin GUI)
- **Python + MetaTrader5**: API oficial dentro de Wine
- **RPyC Server**: Expone funciones MT5 via RPC

### 2. Host (Tu PC)
- **Dashboard Streamlit**: Interface actual
- **Optuna**: Optimizador de parámetros
- **RPyC Client**: Se conecta al contenedor

---

## 📝 Plan de Implementación

### FASE 1: Preparar Docker Image (2-3 horas)

#### 1.1 Crear Dockerfile
```dockerfile
FROM ubuntu:22.04

# Evitar prompts interactivos
ENV DEBIAN_FRONTEND=noninteractive

# Instalar dependencias
RUN apt-get update && apt-get install -y \
    wget \
    software-properties-common \
    xvfb \
    x11vnc \
    supervisor \
    cabextract \
    winbind \
    && rm -rf /var/lib/apt/lists/*

# Instalar Wine
RUN dpkg --add-architecture i386 && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable

# Instalar Winetricks
RUN wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
    chmod +x winetricks && mv winetricks /usr/local/bin/

# Configurar Wine
ENV WINEARCH=win64
ENV WINEPREFIX=/root/.wine
RUN wineboot --init && winetricks -q vcrun2019 corefonts

# Descargar e instalar MT5
RUN wget -O /tmp/mt5setup.exe https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe && \
    xvfb-run wine /tmp/mt5setup.exe /auto && \
    rm /tmp/mt5setup.exe

# Instalar Python en Wine
RUN wget -O /tmp/python-installer.exe https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe && \
    xvfb-run wine /tmp/python-installer.exe /quiet InstallAllUsers=1 PrependPath=1 && \
    rm /tmp/python-installer.exe

# Instalar paquetes Python en Wine
RUN wine pip install MetaTrader5 rpyc numpy pandas

# Copiar scripts
COPY rpyc_mt5_server.py /opt/rpyc_mt5_server.py
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Exponer puertos
EXPOSE 18812 5900

# Comando de inicio
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

#### 1.2 Crear RPyC Server (rpyc_mt5_server.py)
```python
#!/usr/bin/env python3
"""
RPyC Server que expone funciones de MT5 Strategy Tester
"""
import rpyc
from rpyc.utils.server import ThreadedServer
import MetaTrader5 as mt5
import subprocess
import os
import time
import configparser

class MT5TesterService(rpyc.Service):
    
    def on_connect(self, conn):
        print("🔗 Client connected")
        
    def on_disconnect(self, conn):
        print("🔌 Client disconnected")
    
    def exposed_initialize(self, login, password, server):
        """Inicializa MT5 con credenciales"""
        if not mt5.initialize():
            return False, mt5.last_error()
        
        # Login
        authorized = mt5.login(login, password=password, server=server)
        if not authorized:
            return False, mt5.last_error()
        
        return True, "Connected"
    
    def exposed_enable_symbol(self, symbol):
        """Habilita símbolo en Market Watch"""
        return mt5.symbol_select(symbol, True)
    
    def exposed_run_backtest(self, config_dict):
        """
        Ejecuta backtest usando CLI de MT5
        config_dict debe contener: ea_name, symbol, timeframe, date_from, date_to, 
                                   deposit, leverage, parameters
        """
        # Paths
        mt5_path = "/root/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
        reports_dir = "/tmp/mt5_reports"
        os.makedirs(reports_dir, exist_ok=True)
        
        timestamp = int(time.time() * 1000)
        ini_path = f"{reports_dir}/config_{timestamp}.ini"
        report_path = f"{reports_dir}/report_{timestamp}.htm"
        set_path = f"{reports_dir}/params_{timestamp}.set"
        
        # Crear archivo .ini
        config = configparser.ConfigParser()
        config.optionxform = str
        
        config['Common'] = {
            'Login': str(config_dict.get('login', '')),
            'Password': config_dict.get('password', ''),
            'Server': config_dict.get('server', '')
        }
        
        config['Tester'] = {
            'Expert': f"Experts\\{config_dict['ea_name']}",
            'Symbol': config_dict['symbol'],
            'Period': config_dict['timeframe'].replace('PERIOD_', ''),
            'Optimization': '0',
            'Model': '0',
            'Deposit': str(config_dict['deposit']),
            'Currency': 'USD',
            'Leverage': f"1:{config_dict['leverage']}",
            'FromDate': config_dict['date_from'],
            'ToDate': config_dict['date_to'],
            'Report': report_path,
            'ReplaceReport': '1',
            'ShutdownTerminal': '1',  # Auto-cerrar
            'ExpertParameters': os.path.basename(set_path)
        }
        
        with open(ini_path, 'w') as f:
            config.write(f)
        
        # Crear archivo .set con parámetros
        with open(set_path, 'w', encoding='utf-16-le') as f:
            f.write('\ufeff')
            for k, v in config_dict.get('parameters', {}).items():
                val = "true" if v is True else "false" if v is False else str(v)
                f.write(f"{k}={val}\n")
        
        # Copiar .set a Presets folder
        presets_dir = "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Presets"
        os.makedirs(presets_dir, exist_ok=True)
        import shutil
        shutil.copy(set_path, os.path.join(presets_dir, os.path.basename(set_path)))
        
        # Ejecutar MT5 con xvfb
        cmd = f'xvfb-run -a wine "{mt5_path}" /config:"{ini_path}"'
        
        try:
            # Ejecutar y esperar hasta 10 minutos
            result = subprocess.run(cmd, shell=True, timeout=600, 
                                   capture_output=True, text=True)
        except subprocess.TimeoutExpired:
            return {'error': 'Backtest timeout (10 min)'}
        
        # Parsear reporte HTML
        if os.path.exists(report_path):
            return self._parse_report(report_path)
        else:
            return {'error': 'Report not generated'}
    
    def _parse_report(self, html_path):
        """Parsea reporte HTML de MT5"""
        import re
        try:
            with open(html_path, 'r', encoding='utf-8') as f:
                html = f.read()
            
            patterns = {
                'total_net_profit': r'Total Net Profit</td><td[^>]*>([-\d\s.]+)',
                'profit_factor': r'Profit Factor</td><td[^>]*>([\d.]+)',
                'max_drawdown': r'Maximal Drawdown</td><td[^>]*>([\d.]+)',
                'total_trades': r'Total Trades</td><td[^>]*>(\d+)',
                'win_rate': r'Win Rate.*?</td><td[^>]*>([\d.]+)%'
            }
            
            result = {}
            for key, pattern in patterns.items():
                match = re.search(pattern, html, re.IGNORECASE | re.DOTALL)
                if match:
                    val = match.group(1).replace(' ', '').replace('\xa0', '')
                    result[key] = float(val) if val else 0.0
            
            return result
        
        except Exception as e:
            return {'error': str(e)}
    
    def exposed_shutdown(self):
        """Cierra MT5"""
        mt5.shutdown()
        return True

if __name__ == "__main__":
    print("🚀 Starting MT5 RPyC Server on port 18812...")
    server = ThreadedServer(MT5TesterService, port=18812, 
                           protocol_config={'allow_public_attrs': True})
    server.start()
```

#### 1.3 Crear supervisord.conf
```ini
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log

[program:xvfb]
command=/usr/bin/Xvfb :99 -screen 0 1024x768x16
autostart=true
autorestart=true
priority=1

[program:rpyc_server]
command=wine python /opt/rpyc_mt5_server.py
environment=DISPLAY=":99"
autostart=true
autorestart=true
priority=10
stdout_logfile=/var/log/rpyc_server.log
stderr_logfile=/var/log/rpyc_server_error.log
```

---

### FASE 2: Modificar Cliente Python (1 hora)

#### 2.1 Crear RPyC Client (lib/mt5_rpyc_client.py)
```python
"""
Cliente RPyC para conectarse al contenedor Docker con MT5
"""
import rpyc

class MT5RPyCClient:
    def __init__(self, host='localhost', port=18812):
        self.host = host
        self.port = port
        self.conn = None
    
    def connect(self):
        """Conectar al servidor RPyC"""
        self.conn = rpyc.connect(self.host, self.port, 
                                config={'sync_request_timeout': 600})
        return True
    
    def run_backtest(self, ea_name, symbol, timeframe, date_from, date_to, 
                    deposit, leverage, parameters, login, password, server):
        """Ejecutar backtest via RPyC"""
        if not self.conn:
            self.connect()
        
        config = {
            'ea_name': ea_name,
            'symbol': symbol,
            'timeframe': timeframe,
            'date_from': date_from,
            'date_to': date_to,
            'deposit': deposit,
            'leverage': leverage,
            'parameters': parameters,
            'login': login,
            'password': password,
            'server': server
        }
        
        return self.conn.root.run_backtest(config)
    
    def close(self):
        if self.conn:
            self.conn.close()
```

#### 2.2 Modificar mt5_strategy_tester.py
```python
# Agregar al inicio
USE_DOCKER_RPYC = True  # Toggle para usar Docker o local

# En run_backtest():
if USE_DOCKER_RPYC:
    from .mt5_rpyc_client import MT5RPyCClient
    client = MT5RPyCClient(host='localhost', port=18812)
    result = client.run_backtest(
        ea_name=ea_name,
        symbol=symbol,
        timeframe=timeframe,
        date_from=date_from,
        date_to=date_to,
        deposit=deposit,
        leverage=leverage,
        parameters=parameters,
        login='198035354',
        password='Motivo@1',
        server='Exness-MT5Trial11'
    )
    return result
else:
    # Código actual para ejecución local
    ...
```

---

### FASE 3: Build y Deploy (30 min)

#### 3.1 Estructura de Archivos
```
optimization/
├── docker/
│   ├── Dockerfile
│   ├── rpyc_mt5_server.py
│   ├── supervisord.conf
│   └── docker-compose.yml
├── lib/
│   ├── mt5_rpyc_client.py
│   └── mt5_strategy_tester.py (modificado)
└── dashboard.py
```

#### 3.2 docker-compose.yml
```yaml
version: '3.8'

services:
  mt5_tester:
    build: ./docker
    ports:
      - "18812:18812"   # RPyC
      - "5900:5900"     # VNC (opcional, para debug)
    volumes:
      - ./data/mt5:/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5
      - ./reports:/tmp/mt5_reports
    environment:
      - DISPLAY=:99
    restart: unless-stopped
```

#### 3.3 Comandos
```bash
# Build imagen
docker-compose build

# Iniciar contenedor
docker-compose up -d

# Ver logs
docker-compose logs -f mt5_tester

# Probar conexión RPyC
python -c "import rpyc; c = rpyc.connect('localhost', 18812); print('Connected!')"
```

---

### FASE 4: Integración con Optuna (30 min)

Modificar `optimizer_core.py` para usar el cliente RPyC automáticamente.

---

## ⏱️ Timeline Estimado

| Fase | Tarea | Tiempo |
|------|-------|--------|
| 1.1 | Crear Dockerfile | 1 hora |
| 1.2 | Crear RPyC Server | 1 hora |
| 1.3 | Configurar Supervisor | 15 min |
| 2.1 | Crear Cliente RPyC | 30 min |
| 2.2 | Modificar Strategy Tester | 30 min |
| 3.1 | Build Docker Image | 30 min (automático) |
| 3.2 | Testing | 30 min |
| 4 | Integración Optuna | 30 min |
| **TOTAL** | | **~4-5 horas** |

---

## ✅ Ventajas de Esta Arquitectura

1. **100% Automatizado**: Sin intervención manual
2. **Headless**: No requiere GUI ni pantalla
3. **Escalable**: Múltiples contenedores = backtest paralelo
4. **Aislado**: No afecta tu sistema Windows
5. **Portátil**: Funciona en cualquier máquina con Docker
6. **Preciso**: Usa motor real de MT5

---

## ⚠️ Prerequisitos

1. **Docker Desktop** instalado en Windows
2. **WSL2** habilitado (Docker lo usa)
3. **~10GB** espacio para imagen Docker
4. **Cuenta MT5** con credenciales

---

## 🚀 ¿Comenzamos?

¿Quieres que implemente esta solución paso a paso?
