# 📦 ROUDO GOD MODE - Guía de Instalación

## 🚀 Instalación Rápida (5 minutos)

### Paso 1: Compilar el EA

1. Abrir MetaEditor en MT5 (presionar F4 o botón MetaEditor)
2. Navegar a: `File → Open Data Folder`
3. Copiar toda la carpeta `ROUDO` a: `MQL5/Experts/`
4. En MetaEditor, abrir: `Experts/ROUDO/ROUDO_GOD.mq5`
5. Presionar **F7** o click en "Compile"
6. Verificar que dice: "0 errors, 0 warnings" ✅

### Paso 2: Configurar en el Gráfico

1. En MT5, abrir gráfico de **XAUUSD** (cualquier timeframe)
2. Arrastrar `ROUDO_GOD.mq5` desde Navigator al gráfico
3. En la pestaña **"Inputs"**, click en **"Load"**
4. Seleccionar archivo según tu cuenta:
   - `ROUDO_GOD_XAUUSD_500.set` (para cuenta $500)
   - `ROUDO_GOD_XAUUSD_1000.set` (para cuenta $1,000)
5. **IMPORTANTE:** Ajustar `ServerTimeOffset`:
   - Si tu broker está en GMT+0: `ServerTimeOffset = 0`
   - Si tu broker está en GMT+2: `ServerTimeOffset = 2`
   - Si tu broker está en GMT+3: `ServerTimeOffset = 3`
6. Click en **"OK"**

### Paso 3: Activar Auto-Trading

1. Click en botón **"Auto Trading"** (debe verse verde) 🟢
2. Verificar que en esquina superior derecha del gráfico aparece: "😊 ROUDO_GOD"
3. Listo! ✅

---

## 📋 Estructura de Archivos

```
ROUDO/
├── ROUDO_GOD.mq5                       # ⭐ Archivo principal (compilar este)
├── ROUDO.mq5                           # Versión básica (opcional)
│
├── includes/                           # Módulos (NO compilar)
│   ├── R_Config_GOD.mqh
│   ├── R_Killzones.mqh
│   ├── R_TrailingStop.mqh
│   ├── R_Breakeven.mqh
│   ├── R_PartialTP.mqh
│   ├── R_Drawdown.mqh
│   ├── R_MartingalePro.mqh
│   ├── R_Dashboard.mqh
│   └── ... (otros módulos)
│
├── ROUDO_GOD_XAUUSD_500.set            # ⭐ Preset para $500
├── ROUDO_GOD_XAUUSD_1000.set           # Preset para $1,000
├── ROUDO_GOD_PLAN.md                   # Plan de desarrollo
├── README_GOD.md                       # Resumen ejecutivo
├── ROUDO_GOD_OPTIMAL_SETTINGS.txt      # Configuración detallada
└── CHANGELOG_GOD.md                    # Historial de cambios
```

---

## ⚙️ Configuración del ServerTimeOffset

**MUY IMPORTANTE:** El `ServerTimeOffset` debe configurarse según la zona horaria de tu broker para que las killzones funcionen correctamente.

### ¿Cómo saber el offset de mi broker?

1. Abrir gráfico de cualquier par en MT5
2. Mirar la hora actual del servidor (esquina inferior)
3. Comparar con hora GMT actual (Google: "GMT time now")
4. Calcular la diferencia:

**Ejemplos:**
- Servidor muestra 14:00, GMT real es 12:00 → Offset = +2
- Servidor muestra 15:00, GMT real es 12:00 → Offset = +3
- Servidor muestra 12:00, GMT real es 12:00 → Offset = 0

**Brokers comunes:**
- **IC Markets:** GMT+2 (verano) / GMT+3 (invierno)
- **Pepperstone:** GMT+2 (verano) / GMT+3 (invierno)
- **XM:** GMT+2 (verano) / GMT+3 (invierno)
- **FTMO:** GMT+2
- **Alpari:** GMT+0

---

## 🕐 Horarios de Killzones (Después de ajustar offset)

Con `ServerTimeOffset` correcto, el EA operará automáticamente en:

**London-NY Overlap** (⭐ PRINCIPAL):
- Horario EDT: 07:00 - 10:00
- Horario GMT: 12:00 - 15:00
- **Mejor horario para ORO**

**London Open** (SECUNDARIO):
- Horario EDT: 02:00 - 05:00
- Horario GMT: 07:00 - 10:00

**Fuera de estas killzones:** El EA NO abrirá nuevas posiciones (solo gestionará las existentes).

---

## ✅ Verificación Post-Instalación

### 1. Verificar Dashboard

Deberías ver en pantalla:

```
╔═══════════════════════════════════════════════════════════╗
║      ROUDO GOD MODE v3.0 - THE TITAN SCALPER          ║
╠═══════════════════════════════════════════════════════════╣
║ 📊 ESTADÍSTICAS DIARIAS                               ║
║ Profit Diario: $0.00 / $50.00                         ║
║ ...                                                    ║
╠═══════════════════════════════════════════════════════════╣
║ ⏰ KILLZONE STATUS                                     ║
║ Actual: FUERA DE KILLZONE ⏸️ (PAUSADO)               ║
║ Próxima: LONDON-NY OVERLAP (en Xh Xm)                 ║
╚═══════════════════════════════════════════════════════════╝
```

### 2. Verificar Logs (Terminal → Expert)

Deberías ver:

```
╔════════════════════════════════════════════════════════════╗
║                    ROUDO GOD MODE v3.0                     ║
║                  THE TITAN SCALPER PRO                     ║
╠════════════════════════════════════════════════════════════╣
✓ Símbolo inicializado: XAUUSD
✓ Trade configurado (Magic: 11111)
✓ Indicadores inicializados (MACD M1, ATR 14)
...
🚀 ROUDO GOD MODE v3.0 LISTO PARA OPERAR
```

### 3. Verificar Configuración

En pestaña "Inputs":
- `UseKillzones = true` ✅
- `TradeLondonNYOverlap = true` ✅
- `UseFibonacciProgression = true` ✅
- `UseTrailingStop = true` ✅
- `UseBreakeven = true` ✅
- `UsePartialTP = true` ✅

---

## 🔧 Solución de Problemas

### ❌ Error: "Cannot load expert"
**Solución:** Verificar que copiaste toda la carpeta `includes/` junto con `ROUDO_GOD.mq5`

### ❌ Error: "DLL calls are not allowed"
**Solución:** En configuración del EA, pestaña "Common", activar "Allow DLL imports" (si es necesario)

### ❌ Error: "Auto trading is disabled"
**Solución:** Click en botón "Auto Trading" en barra superior de MT5 (debe verse verde)

### ⚠️ Warning: "Trading is not allowed for this symbol"
**Solución:** Verificar que el símbolo sea XAUUSD y que trading esté permitido en propiedades del símbolo

### ⏸️ EA no abre posiciones
**Posibles causas:**
1. **Fuera de killzone:** Normal, esperará próxima killzone
2. **Meta diaria alcanzada:** Pausado hasta mañana
3. **Spread muy alto:** Esperando spread < 30 pips
4. **Sin señal MACD:** Esperando cruce MACD en M1
5. **Drawdown excedido:** Pausado por seguridad

---

## 📊 Monitoreo Recomendado

### Diario
- ✅ Verificar profit diario vs meta ($50 para cuenta $500)
- ✅ Revisar drawdown actual
- ✅ Confirmar que opera solo en killzones
- ✅ Verificar nivel de margen (>800%)

### Semanal
- ✅ Analizar win rate (objetivo >70%)
- ✅ Revisar profit factor (objetivo >1.8)
- ✅ Evaluar drawdown máximo semanal
- ✅ Ajustar parámetros si es necesario

---

## ⚠️ ADVERTENCIAS IMPORTANTES

1. **SIEMPRE testear en DEMO primero** (mínimo 1 mes)
2. **NUNCA** operar con dinero que no puedes perder
3. **VPS recomendado** para trading 24/7
4. **Monitorear diariamente** el drawdown
5. **Respetar** las killzones configuradas
6. **NO modificar** parámetros durante rachas perdedoras

---

## 📞 Soporte

Para preguntas o problemas:
1. Revisar documentación: `ROUDO_GOD_PLAN.md`
2. Consultar settings: `ROUDO_GOD_OPTIMAL_SETTINGS.txt`
3. Ver changelog: `CHANGELOG_GOD.md`

---

**Versión:** ROUDO GOD MODE v3.0
**Fecha:** 2026-01-24
**Status:** ✅ PRODUCTION READY

---

*THE TITAN SCALPER - Professional Trading System*
*Desarrollado por ROUDO Company*
