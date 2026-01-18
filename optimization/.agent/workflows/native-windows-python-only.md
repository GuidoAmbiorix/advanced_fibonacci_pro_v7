# 🎯 Plan: Native Windows MT5 Optimization (100% Python)
## Streamlit + FastAPI + Real-Time Updates

---

## 📋 Objetivos

1. ✅ **Eliminar Docker/Wine** - Todo nativo en Windows
2. ✅ **100% Python** - No JavaScript/React
3. ✅ **Real-Time Updates** - Ver backtests en vivo
4. ✅ **UI/UX Premium** - Streamlit moderno
5. ✅ **MT5 Nativo** - terminal64.exe directo

---

## 🏗️ Arquitectura (Todo Python)

```
Stack Tecnológico:
├── Streamlit (Frontend UI)
├── FastAPI (Backend API - opcional)
├── Threading (Real-time updates)
├── Optuna (Optimización)
├── SQLite (Database)
├── Plotly (Gráficos interactivos)
└── MT5 Native (subprocess)
```

---

## 📁 Estructura de Carpetas

```
optimization/                       # ← Carpeta principal (ya existe)
├── dashboard.py                    # Streamlit UI (actualizar)
├── lib/
│   ├── optimizer_core.py          # Optuna logic (actualizar)
│   ├── mt5_native.py              # ← NUEVO: MT5 Windows nativo
│   ├── realtime_updater.py        # ← NUEVO: Real-time updates
│   └── ui_components.py           # ← NUEVO: Streamlit components
├── data/
│   ├── optimization.db            # SQLite (ya existe)
│   ├── ea_sources/                # EAs source
│   └── ea_compiled/               # EAs compiled
├── config/
│   └── settings.py                # ← NUEVO: Configuración
└── requirements.txt               # Python dependencies

# ELIMINAR:
├── docker-compose.yml             # ❌ Borrar
├── mt5/Dockerfile                 # ❌ Borrar
└── mt5/compile_api.py             # ❌ Borrar
```

---

## 🔄 Flujo de Trabajo

### **Proceso de Optimización con Real-Time:**

```python
# 1. Usuario configura optimización en Streamlit
# 2. Backend ejecuta trials en thread separado
# 3. Cada trial actualiza session_state
# 4. Streamlit auto-refresca (st.rerun())
# 5. Gráficos se actualizan en vivo
```

### **Diagrama:**

```
User → Streamlit UI → optimizer_core.py → mt5_native.py → MT5.exe
         ↑                    ↓
         ↑              SQLite + Cache
         ↑                    ↓
         └────── Real-time Updates (threading)
```

---

## 🔧 Implementación Detallada

### **1. mt5_native.py** (NUEVO)

```python
"""
Interfaz nativa para MT5 en Windows.
Reemplaza completamente la API de Docker/Wine.
"""
import subprocess
import os
from pathlib import Path
import xml.etree.ElementTree as ET
import tempfile

class MT5Windows:
    def __init__(self):
        self.mt5_path = self._find_mt5()
        self.terminal_exe = self.mt5_path / "terminal64.exe"
    
    def _find_mt5(self) -> Path:
        """Detecta instalación MT5 automáticamente"""
        common_paths = [
            Path("C:/Program Files/MetaTrader 5"),
            Path.home() / "AppData/Roaming/MetaQuotes/Terminal",
        ]
        for path in common_paths:
            if path.exists() and (path / "terminal64.exe").exists():
                return path
        raise FileNotFoundError("MT5 no encontrado!")
    
    def run_backtest(self, ea_path: str, symbol: str, 
                     timeframe: str, date_from: str, date_to: str,
                     deposit: float, parameters: dict,
                     progress_callback=None) -> dict:
        """
        Ejecuta backtest y retorna resultados.
        progress_callback: función para updates en vivo
        """
        # 1. Crear tester.ini
        ini_file = self._create_ini(
            ea_path, symbol, timeframe, 
            date_from, date_to, deposit, parameters
        )
        
        # 2. Path para report
        report_file = tempfile.mktemp(suffix='.htm')
        
        # 3. Ejecutar MT5
        cmd = [
            str(self.terminal_exe),
            f"/config:{ini_file}",
            "/portable"
        ]
        
        if progress_callback:
            progress_callback("Iniciando MT5...", 0)
        
        # 4. Run subprocess
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600  # 10 min max
        )
        
        if progress_callback:
            progress_callback("Parseando resultados...", 90)
        
        # 5. Parse report
        metrics = self._parse_report(report_file)
        
        # 6. Cleanup
        os.unlink(ini_file)
        if os.path.exists(report_file):
            os.unlink(report_file)
        
        if progress_callback:
            progress_callback("Completado", 100)
        
        return metrics
    
    def _create_ini(self, ea_path, symbol, timeframe, 
                    date_from, date_to, deposit, params):
        """Crea archivo tester.ini para MT5"""
        ini_content = f"""[Tester]
Expert={ea_path}
Symbol={symbol}
Period={timeframe}
Optimization=0
Model=1
Visual=0
FromDate={date_from}
ToDate={date_to}
Deposit={deposit}
Currency=USD
Leverage=500
Report={{report_path}}
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
"""
        # Agregar parámetros
        for key, value in params.items():
            if isinstance(value, bool):
                val = "true" if value else "false"
            else:
                val = str(value)
            ini_content += f"{key}={val}\n"
        
        # Guardar
        ini_file = tempfile.mktemp(suffix='.ini')
        with open(ini_file, 'w') as f:
            f.write(ini_content)
        
        return ini_file
    
    def _parse_report(self, report_path: str) -> dict:
        """Parse HTML/XML report de MT5"""
        if not os.path.exists(report_path):
            return {"profit_factor": 0.0, "error": "No report"}
        
        try:
            tree = ET.parse(report_path)
            root = tree.getroot()
            
            metrics = {}
            for row in root.findall(".//Row"):
                name = row.find("Name")
                value = row.find("Value")
                if name is not None and value is not None:
                    key = name.text.strip()
                    if "Profit Factor" in key:
                        metrics["profit_factor"] = float(value.text)
                    # Agregar más métricas...
            
            return metrics
        except Exception as e:
            return {"profit_factor": 0.0, "error": str(e)}
```

### **2. realtime_updater.py** (NUEVO)

```python
"""
Sistema de actualizaciones en tiempo real para Streamlit.
Usa threading + session_state.
"""
import streamlit as st
import threading
import time
from queue import Queue

class RealtimeUpdater:
    def __init__(self):
        self.update_queue = Queue()
        self.running = False
    
    def start_optimization(self, config, callback):
        """Inicia optimización en thread separado"""
        self.running = True
        
        def run_optimization():
            from lib.optimizer_core import run_optimization
            
            # Ejecutar con callback
            run_optimization(
                config=config,
                progress_callback=lambda msg, pct: self.emit_update({
                    'type': 'progress',
                    'message': msg,
                    'percent': pct
                }),
                trial_callback=lambda trial_data: self.emit_update({
                    'type': 'trial_complete',
                    'data': trial_data
                })
            )
            
            self.running = False
            callback()
        
        thread = threading.Thread(target=run_optimization, daemon=True)
        thread.start()
    
    def emit_update(self, data: dict):
        """Emite actualización"""
        self.update_queue.put(data)
    
    def get_updates(self):
        """Obtiene actualizaciones pendientes"""
        updates = []
        while not self.update_queue.empty():
            updates.append(self.update_queue.get())
        return updates
```

### **3. ui_components.py** (NUEVO)

```python
"""
Componentes UI reutilizables para Streamlit.
"""
import streamlit as st
import plotly.graph_objects as go
from datetime import datetime

def show_live_progress(current_trial: int, total_trials: int, 
                       current_pf: float, best_pf: float):
    """Progress bar animado con métricas"""
    
    col1, col2, col3 = st.columns(3)
    
    with col1:
        st.metric("Trial", f"{current_trial}/{total_trials}")
    
    with col2:
        st.metric("Current PF", f"{current_pf:.2f}")
    
    with col3:
        delta = current_pf - best_pf if best_pf > 0 else 0
        st.metric("Best PF", f"{best_pf:.2f}", 
                  delta=f"{delta:+.2f}")
    
    # Progress bar
    progress = current_trial / total_trials if total_trials > 0 else 0
    st.progress(progress, text=f"Optimizando... {progress*100:.1f}%")

def show_live_chart(trial_history: list):
    """Gráfico de profit factor en tiempo real"""
    
    if not trial_history:
        st.info("Esperando datos...")
        return
    
    trials = [t['trial'] for t in trial_history]
    pfs = [t['profit_factor'] for t in trial_history]
    
    fig = go.Figure()
    
    # Línea principal
    fig.add_trace(go.Scatter(
        x=trials,
        y=pfs,
        mode='lines+markers',
        name='Profit Factor',
        line=dict(color='#10b981', width=2),
        marker=dict(size=6)
    ))
    
    # Mejor valor (línea horizontal)
    best_pf = max(pfs)
    fig.add_hline(
        y=best_pf, 
        line_dash="dash", 
        line_color="gold",
        annotation_text=f"Best: {best_pf:.2f}"
    )
    
    fig.update_layout(
        title="Profit Factor por Trial (Live)",
        xaxis_title="Trial",
        yaxis_title="Profit Factor",
        template="plotly_dark",
        height=400
    )
    
    st.plotly_chart(fig, use_container_width=True)

def show_top_parameters(trials: list, top_n: int = 5):
    """Muestra top N parámetros en tiempo real"""
    
    if not trials:
        return
    
    # Ordenar por profit factor
    sorted_trials = sorted(
        trials, 
        key=lambda x: x.get('profit_factor', 0), 
        reverse=True
    )[:top_n]
    
    st.subheader("🏆 Top Parámetros (Live)")
    
    for i, trial in enumerate(sorted_trials, 1):
        with st.expander(
            f"#{i} - PF: {trial['profit_factor']:.2f}", 
            expanded=(i == 1)
        ):
            cols = st.columns(3)
            params = trial.get('params', {})
            
            for j, (key, value) in enumerate(params.items()):
                col_idx = j % 3
                with cols[col_idx]:
                    st.metric(key, value)
```

### **4. dashboard.py** (ACTUALIZAR)

```python
"""
Dashboard principal con real-time updates.
"""
import streamlit as st
from lib.realtime_updater import RealtimeUpdater
from lib.ui_components import *
import time

# Configuración página
st.set_page_config(
    page_title="Optima AI - Live Optimization",
    page_icon="🎯",
    layout="wide"
)

# CSS personalizado
st.markdown("""
<style>
    .stApp {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    }
    .metric-card {
        background: rgba(255,255,255,0.1);
        backdrop-filter: blur(10px);
        border-radius: 10px;
        padding: 20px;
    }
</style>
""", unsafe_allow_html=True)

# Session state
if 'updater' not in st.session_state:
    st.session_state.updater = RealtimeUpdater()
if 'trial_history' not in st.session_state:
    st.session_state.trial_history = []
if 'running' not in st.session_state:
    st.session_state.running = False

# Header
st.title("🎯 Optima AI - Live Optimization")

# Tabs
tab1, tab2, tab3 = st.tabs(["⚡ Live", "📊 Results", "⚙️ Settings"])

with tab1:
    # Live Optimization
    
    if st.session_state.running:
        # Obtener updates
        updates = st.session_state.updater.get_updates()
        
        for update in updates:
            if update['type'] == 'trial_complete':
                st.session_state.trial_history.append(update['data'])
                st.rerun()  # Refrescar UI
        
        # Mostrar estado actual
        if st.session_state.trial_history:
            current = st.session_state.trial_history[-1]
            best = max(st.session_state.trial_history, 
                      key=lambda x: x['profit_factor'])
            
            show_live_progress(
                len(st.session_state.trial_history),
                st.session_state.n_trials,
                current['profit_factor'],
                best['profit_factor']
            )
            
            show_live_chart(st.session_state.trial_history)
            show_top_parameters(st.session_state.trial_history)
        
        # Auto-refresh cada 1 segundo
        time.sleep(1)
        st.rerun()
    
    else:
        # Formulario de configuración
        with st.form("optimization_config"):
            col1, col2 = st.columns(2)
            
            with col1:
                ea_path = st.text_input("EA Path")
                symbol = st.selectbox("Symbol", ["XAUUSD", "EURUSD"])
                n_trials = st.number_input("Trials", 10, 1000, 100)
            
            with col2:
                timeframe = st.selectbox("Timeframe", ["H1", "H4", "D1"])
                date_from = st.date_input("From")
                date_to = st.date_input("To")
            
            submit = st.form_submit_button("🚀 Start Optimization")
            
            if submit:
                config = {
                    'ea_path': ea_path,
                    'symbol': symbol,
                    'n_trials': n_trials,
                    # ... más config
                }
                
                st.session_state.running = True
                st.session_state.n_trials = n_trials
                st.session_state.trial_history = []
                
                st.session_state.updater.start_optimization(
                    config,
                    callback=lambda: setattr(st.session_state, 'running', False)
                )
                
                st.rerun()

with tab2:
    st.subheader("📊 Historical Results")
    # Cargar desde DB...

with tab3:
    st.subheader("⚙️ Settings")
    # Configuración...
```

---

## 📦 Instalación

### **1. Requirements (ACTUALIZAR)**

```txt
# requirements.txt
streamlit>=1.30.0
optuna>=3.5.0
pandas>=2.0.0
plotly>=5.18.0
sqlalchemy>=2.0.0
```

### **2. Instalar**

```bash
cd C:\Users\Ing Guido\Desktop\Proyectos\advanced_fibonacci_pro_v7\optimization
pip install -r requirements.txt
```

### **3. Ejecutar**

```bash
streamlit run dashboard.py
```

---

## 🚀 Migración Paso a Paso

### **Día 1: Backend Nativo**
1. ✅ Crear `mt5_native.py`
2. ✅ Actualizar `optimizer_core.py` para usar MT5 nativo
3. ✅ Probar backtest simple

### **Día 2: Real-Time Updates**
1. ✅ Crear `realtime_updater.py`
2. ✅ Integrar threading en optimizer
3. ✅ Probar updates en vivo

### **Día 3: UI/UX**
1. ✅ Crear `ui_components.py`
2. ✅ Actualizar `dashboard.py` con tabs
3. ✅ Agregar gráficos Plotly

### **Día 4: Polish**
1. ✅ CSS personalizado
2. ✅ Animaciones
3. ✅ Error handling

### **Día 5: Testing**
1. ✅ Probar optimización completa
2. ✅ Validar resultados vs Docker
3. ✅ Documentar

---

## ✅ Resultado Final

**Un sistema que:**
- ⚡ Corre 4x más rápido (sin Docker/Wine)
- 📊 Muestra resultados en tiempo real
- 🎨 UI moderna con Plotly
- 🐍 100% Python
- 💻 100% Windows nativo
- 📁 Todo en carpeta `optimization/`

---

**¿Empezamos con Día 1 (Backend Nativo)?**
