# 🚀 TMAIBNE — Autonomous Trading Intelligence Platform

### Sales, Product & Brand Plan

> **Fecha:** Marzo 2026 | **Autor:** Guido Ambiorix | **Versión:** 2.1

---

## 🎨 IDENTIDAD DE MARCA: TMAIBNE

| Elemento               | Definición                                                                                        |
| ---------------------- | ------------------------------------------------------------------------------------------------- |
| **Nombre**             | TMAIBNE                                                                                           |
| **Tagline**            | _Trade Like Institutions. Managed by Intelligence._                                               |
| **Propuesta de valor** | Sistema de trading algorítmico institucional + gestión de riesgo cloud para traders de prop firms |
| **Paleta**             | Negro profundo `#0A0A0F` · Dorado `#D4AF37` · Azul eléctrico `#00D4FF` · Blanco `#F5F5F5`         |
| **Tipografía**         | Inter (headings) + Roboto Mono (datos/métricas)                                                   |
| **Audiencia**          | Traders de prop firms (GOAT, FTMO, MyFXBook), HFT hobbyists, gestores de portafolio retail        |
| **Tono**               | Institucional · Preciso · Confiable · Premium                                                     |

---

## EL PRODUCTO: Dos Componentes, Un Sistema

El sistema está compuesto por **dos EAs altamente sofisticados** que trabajan juntos. Ambos son vendibles como productos independientes o como un bundle completo.

```
┌──────────────────────────────────────────────────────────────────────┐
│                    SISTEMA COMPLETO                                   │
│                                                                        │
│   🤖 Symbol Engine          +        🧠 Portfolio Governor            │
│   (Agente de Trading)                (Cerebro de Riesgo Central)      │
│                                                                        │
│   Opera por símbolo                  Opera en 1 solo chart            │
│   Genera señales                     Supervisa todo el portafolio      │
│   Ejecuta órdenes                    Protege el drawdown               │
│   Aprende de sus trades              Coordina todos los Symbol Engines │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 🤖 PRODUCTO 1: Symbol Engine — El Agente de Trading

### Qué hace

Un Expert Advisor completamente autónomo que opera **un símbolo** en MT5. Implementa una estrategia institucional completa de múltiples capas de confluencia, incluyendo los conceptos más avanzados de Smart Money, análisis multi-temporal y machine learning adaptativo.

### Módulos del Symbol Engine

| Categoría                | Módulos                 | Descripción                                                    |
| ------------------------ | ----------------------- | -------------------------------------------------------------- |
| **Smart Money Concepts** | `SMC_StructureBreak`    | Detecta BOS (Break of Structure) y CHoCH (Change of Character) |
|                          | `SMC_OrderBlocks`       | Identifica bloques institucionales de órdenes                  |
|                          | `SMC_FairValueGap`      | Detecta y opera Fair Value Gaps                                |
|                          | `SMC_LiquiditySweep`    | Detecta barridos de liquidez y trampolines                     |
| **Confluencia Multi-TF** | `MTF_Confluence`        | Alineación de tendencia en 3 timeframes (HTF + MTF + actual)   |
|                          | `RSI` momentum          | Filtro de momentum adaptativo                                  |
|                          | `EMA 200` tendencia     | Filtro de tendencia principal                                  |
|                          | `Fibonacci` 0.618/0.786 | Zonas de entrada de precisión                                  |
| **Análisis Avanzado**    | `VolumeAnalysis`        | Volumen institucional y delta                                  |
|                          | `Divergence`            | Divergencias RSI/precio                                        |
|                          | `Inst_Concepts`         | Breaker Blocks, Macro Windows, Power of 3, Wyckoff             |
|                          | `MetalsAnalysis`        | Módulo especializado para XAUUSD                               |
| **Filtros de Sesión**    | `KillzoneConfig`        | London Open, New York, Asian, London Close                     |
|                          | `NewsFilter`            | Filtro de calendario económico + detección de flash crash      |
|                          | `SessionOptimizer`      | Maximiza performance por sesión                                |
| **Machine Learning**     | `Learning_MFE_MAE`      | Aprende MFE/MAE histórico para optimizar TP/SL                 |
|                          | `PatternMemory`         | Memoriza patrones de confluencia ganadores                     |
|                          | `PatternRecognizer`     | Reconoce patrones similares a los históricos                   |
|                          | `PerformanceAnalyzer`   | Analiza el performance propio y ajusta parámetros              |
|                          | `DatabaseManager`       | Persistencia SQLite de todo el historial                       |
| **Gestión Adaptativa**   | `AdaptiveRiskManager`   | Ajusta el riesgo automáticamente según el performance          |
|                          | `AdaptiveExitManager`   | Aprende cuándo cerrar (trail, BE, TP)                          |
|                          | `AdaptiveFilterManager` | Ajusta el umbral de confluencia dinámicamente                  |
| **Sizing**               | `KellyPositionSizer`    | Kelly fraccionario con límites por cuenta                      |
|                          | `GovernorAllocator`     | Solicita permiso de riesgo al Governor                         |
| **Protecciones**         | `FailSafe`              | Checks de seguridad en cada tick                               |
|                          | `KillSwitch`            | Parada de emergencia automática                                |
|                          | `MarketRegime`          | Detección de trending/ranging/chaos                            |
| **Ejecución**            | Circuit Breaker         | Límite diario en R, cooldown tras pérdidas                     |
|                          | Anti-correlación        | Bloquea entradas en símbolo del mismo grupo                    |
|                          | EOD Close               | Cierra posiciones intra-day al fin del día                     |

### Parámetros Clave de Trading

```
Fib Levels:      0.618 / 0.786 (zonas de alta probabilidad)
Confluencia:     Umbral mínimo configurable (típico: 14/30)
TP Modes:        Fijo / Adaptativo / Híbrido / Volatilidad
Trail:           R-based / Chandelier / Step (con decay adaptativo)
Parciales:       Cierre parcial configurable (% de la posición)
Risk/Trade:      Base % configurado por prop firm
Kelly:           Half Kelly por defecto (0.5 fracción)
Add-Ons:         Hasta 2 entradas adicionales en el mismo trade
Max Posiciones:  Configurable por símbolo
Sesiones:        London Open + NY (configurado para GOAT Funding)
```

---

## 🧠 PRODUCTO 2: Portfolio Governor — El Cerebro de Riesgo

### Qué hace

Un EA supervisor que corre en **un solo chart** y controla a todos los Symbol Engines del portafolio mediante un bus de comunicación interno (GlobalVariables de MT5). Es el responsable de que **nunca se violen las reglas de la prop firm**.

### Los 6 Motores del Governor

| Motor                         | Regla                                  | Acción                        |
| ----------------------------- | -------------------------------------- | ----------------------------- |
| **DD Governor**               | Peak-to-trough en %                    | Reduce riesgo → pausa trading |
| **Rolling PF**                | Profit Factor últimos 30 trades        | Reduce riesgo → pausa trading |
| **DD Diario/Semanal/Mensual** | Límites configurables por período      | Pausa trading del período     |
| **Daily Target**              | Objetivo diario en $                   | Cierra todas y para el día    |
| **Exposure Controller**       | Cap total % / por símbolo / por grupo  | Ajusta tamaño de posición     |
| **Correlation Guard**         | Bloquea la 3ra posición correlacionada | Bloqueo de entrada            |

### Umbrales actuales (Goat Funding $2500)

```
DD Normal:         1.5%  →  Continúa al 100%
DD Reduced:        2.5%  →  Risk × 0.75
DD Pause:          3.5%  →  STOP (GOAT máximo: 4%)
PF Normal:         1.8   →  Continúa al 100%
PF Reduced:        1.2   →  Risk × 0.70
PF Pause:          1.0   →  STOP (tras 20+ trades)
Daily DD:          2.5%  →  STOP por hoy
Weekly DD:         3.5%  →  STOP por semana
Daily Target:      $10   →  Cierra todo, para por hoy
Portfolio Total:   3.0%  →  No más entradas
Por Símbolo:       0.6%  →  Cap por instrumento
Por Grupo:         2.0%  →  Cap USD/JPY/GBP/Metals
```

---

## 🌐 PRODUCTO 3: GovernorAI — El SaaS (Cloud)

### Visión

Convertir el sistema completo en una **plataforma cloud multi-cuenta** que:

- Se conecta a cualquier cuenta MT5 vía Bridge EA
- Replica toda la lógica del Governor desde la nube
- Ofrece dashboard web + mobile en tiempo real
- Soporta múltiples usuarios y cuentas (multi-tenant)
- Vende suscripciones mensuales a traders de prop firms

### Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                  MT5 Terminal (cliente)                          │
│  Bridge EA → envía telemetría + recibe señales cada 5s         │
│  Symbol Engines → no cambian, siguen GV_TRADING_ENABLED        │
└──────────────────────────────┬──────────────────────────────────┘
                               │ HTTPS / WebSocket
┌──────────────────────────────▼──────────────────────────────────┐
│                  GovernorAI Cloud                                │
│  FastAPI backend  │  Python Risk Engine  │  Redis pub-sub       │
│  PostgreSQL + TimescaleDB  │  Alert Service  │  Auth JWT        │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│  Next.js Web Dashboard (PWA)                                     │
│  Equity curve │ DD gauge │ Posiciones live │ Signal ranking     │
└─────────────────────────────────────────────────────────────────┘
```

### Mapeo MQL5 → Cloud

| Función MQL5                            | Equivalente SaaS                                      |
| --------------------------------------- | ----------------------------------------------------- |
| `GlobalVariableSet(GV_TRADING_ENABLED)` | Bridge EA hace poll `GET /api/v1/signals/{accountId}` |
| `UpdateRiskMultiplier()`                | Python `RiskEngine.compute_multiplier(state)`         |
| `CalculatePortfolioMetrics()`           | WebSocket push en cada evento de posición             |
| `CanOpenTrade()`                        | `GET /api/v1/can-open?symbol=&risk=`                  |
| Matriz correlación hardcodeada          | Motor dinámico: rolling 120-bar via TimescaleDB       |
| `CloseAllPositions()`                   | Comando WebSocket → Bridge EA → MT5                   |
| CSV transaction log                     | Tabla `deal_events` + exportar a CSV/Excel            |
| Dashboard en chart                      | Web Dashboard en tiempo real                          |
| `RankManager.UpdateRanks()`             | Scoring cloud-side → dashboard live                   |

---

## 📦 MODELOS DE VENTA

### Opción A — Venta de EA (B2C, traders individuales)

| Producto               | Precio        | Incluye                                               |
| ---------------------- | ------------- | ----------------------------------------------------- |
| **Symbol Engine** solo | $299 one-time | 1 licencia, 1 cuenta MT5                              |
| **Governor** solo      | $149 one-time | Ilimitadas instancias locales                         |
| **Bundle Completo**    | $399 one-time | Symbol Engine + Governor + configuración inicial      |
| **Bundle + Setup**     | $599 one-time | Todo + 1h de onboarding + configuración de .set files |

### Opción B — GovernorAI SaaS (B2C/B2B, subscripción mensual)

| Tier           | Precio  | Cuentas                | Features                                     |
| -------------- | ------- | ---------------------- | -------------------------------------------- |
| **Starter**    | $0/mes  | 1 cuenta, 7 días       | Dashboard básico + alertas email             |
| **Pro**        | $29/mes | 3 cuentas              | Risk engine completo, Telegram, CSV exports  |
| **Team**       | $79/mes | 10 cuentas, API access | Multi-usuario, correlation heatmap, webhooks |
| **Enterprise** | Custom  | Ilimitado + whitelabel | Reglas custom, SLA, soporte prioritario      |

### Opción C — Whitelabel para Prop Firms

Vender el sistema completo (EAs + SaaS) a **prop firms** que quieran ofrecerlo a sus traders:

- Firma tiene su propio dashboard brandado
- Trader recibe los EAs pre-configurados para esa prop firm
- Prop firm paga royalty mensual o fee de licencia

---

## 🗺️ HOJA DE RUTA

### 🚀 Fase 1 — MVP SaaS (8 semanas)

- [ ] Bridge EA: telemetría via `WebRequest()` + poll de señales
- [ ] FastAPI: `/telemetry` + `/signals` endpoints
- [ ] PostgreSQL: accounts, positions, deals, risk_snapshots (TimescaleDB)
- [ ] Python Risk Engine: porta Governor completo con tests unitarios
- [ ] Dashboard: equity curve, DD gauge, tabla posiciones en tiempo real
- [ ] Auth: JWT + API key para Bridge EA
- [ ] Alertas: Telegram bot
- [ ] Deploy: Railway

**Entregable:** Un usuario real monitoreando su cuenta MT5 desde el browser.

### 📈 Fase 2 — Multi-cuenta & Analytics (6 semanas)

- [ ] Multi-tenant: organizaciones, roles Admin/Viewer
- [ ] Motor de correlación dinámico (rolling price data)
- [ ] Analytics: win rate histórico, tendencia de PF, equity D/W/M
- [ ] UI de configuración de riesgo (reemplaza archivos `.set`)
- [ ] Exportación de reportes (CSV, PDF)

**Entregable:** Equipos pequeños de traders usándolo.

### 🧠 Fase 3 — AI & Automation (8 semanas)

- [ ] Config automático de umbrales por prop firm (GOAT, FTMO, MyFXBook)
- [ ] Heatmap de correlación interactivo en tiempo real
- [ ] Comparación H1 vs H4 performance
- [ ] Mobile PWA con push notifications
- [ ] Webhooks n8n / Zapier / Make
- [ ] Port del `RankManager` al cloud → ranking de señales visible en dashboard

**Entregable:** Plataforma lista para lanzamiento público.

### 🌐 Fase 0 — Landing Page TMAIBNE (Paralela a Fase 1)

- [ ] `landing/index.html` — página de ventas completa (single-page)
- [ ] `landing/style.css` — dark mode, glassmorphism, animaciones CSS
- [ ] `landing/app.js` — scroll animations, counters, interactividad
- [ ] Secciones: Hero · Productos · Precios · Cómo funciona · FAQ · CTA
- [ ] Formulario waitlist (conectado a n8n o Mailchimp)
- [ ] Deploy: Vercel / Netlify (gratis)

**Entregable:** URL pública lista para compartir y capturar leads antes del MVP.

### 💰 Fase 4 — Comercialización (ongoing)

- [ ] Stripe billing integrado
- [ ] Onboarding automatizado (email sequence)
- [ ] Marketplace de configs/set-files por prop firm
- [ ] API pública para copy trading integrations
- [ ] Whitelabel para prop firms

---

## 🛠️ STACK TECNOLÓGICO

| Capa           | Tecnología                         | Justificación                                 |
| -------------- | ---------------------------------- | --------------------------------------------- |
| Bridge EA      | MQL5                               | Integración nativa MT5 sin libs externas      |
| Backend        | **FastAPI** (Python)               | Async, auto-docs, rápido, porta lógica MQL5   |
| Risk Engine    | **Python** (numpy, pandas)         | Porta lógica MQL5 línea a línea + tests       |
| Base de datos  | **PostgreSQL + TimescaleDB**       | Time-series optimizado para ticks y snapshots |
| Cache / Queue  | **Redis + BullMQ**                 | Pub-sub tiempo real + cola de alertas         |
| Frontend       | **Next.js 14**                     | SSR + ecosistema de charts                    |
| Charts         | **TradingView Lightweight Charts** | Look & feel similar a MT5                     |
| Auth           | **Supabase Auth**                  | JWT + OAuth, multi-tenant built-in            |
| Hosting MVP    | **Railway**                        | Mínimo overhead operacional para empezar      |
| Hosting escala | **AWS ECS + RDS**                  | Producción con alta disponibilidad            |
| Monitoring     | **Sentry + Grafana**               | Errores + métricas de negocio                 |

---

## 📊 SCHEMA BASE DE DATOS (CORE)

```sql
-- Cuentas MT5
CREATE TABLE accounts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES users(id),
  broker      VARCHAR(50),
  login       BIGINT,
  name        VARCHAR(100),
  risk_config JSONB,   -- todos los InpXxx del Governor
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Snapshots de riesgo (time-series, cada 5s)
CREATE TABLE risk_snapshots (
  time               TIMESTAMPTZ NOT NULL,
  account_id         UUID,
  equity             NUMERIC,
  balance            NUMERIC,
  peak_equity        NUMERIC,
  current_dd_pct     NUMERIC,
  daily_dd_pct       NUMERIC,
  weekly_dd_pct      NUMERIC,
  rolling_pf         NUMERIC,
  total_exposure_pct NUMERIC,
  risk_multiplier    NUMERIC,
  trading_enabled    BOOLEAN
);
SELECT create_hypertable('risk_snapshots', 'time');

-- Trades cerrados (para PF y analytics)
CREATE TABLE deal_events (
  id          BIGINT PRIMARY KEY,
  account_id  UUID,
  ticket      BIGINT,
  symbol      VARCHAR(20),
  magic       BIGINT,
  profit      NUMERIC,
  swap        NUMERIC,
  commission  NUMERIC,
  close_time  TIMESTAMPTZ,
  entry_type  VARCHAR(20),
  confluence_score NUMERIC  -- capturado desde Symbol Engine
);

-- Métricas del Symbol Engine (por símbolo)
CREATE TABLE engine_metrics (
  time           TIMESTAMPTZ NOT NULL,
  account_id     UUID,
  symbol         VARCHAR(20),
  confluence_buy NUMERIC,
  confluence_sell NUMERIC,
  market_regime  VARCHAR(20),
  killzone_active BOOLEAN,
  daily_trades   INTEGER,
  daily_r        NUMERIC
);
SELECT create_hypertable('engine_metrics', 'time');
```

---

## ⚡ PROXIMOS PASOS

### Inmediatos (esta semana)

1. **Landing Page TMAIBNE** — `landing/index.html` con todas las secciones de venta
2. **Dominio + Deploy** — registrar `tmaibne.com` y publicar en Vercel
3. **Waitlist** — formulario de captura de emails integrado

### Semana 2 (MVP Backend)

4. **Bridge EA:** porta `ProcessGovernorUpdate()` a emisor de telemetría via `WebRequest()`
5. **FastAPI project:** scaffold con `/api/v1/telemetry`, `/api/v1/signals`, `/api/v1/metrics`
6. **PostgreSQL:** tablas + hypertables + seed `risk_config` para GOAT Funding
7. **Python Risk Engine:** `RiskEngine` con `compute_multiplier()`, `update_trading_status()`, `can_open_trade()` + tests
8. **Next.js dashboard:** `EquityCurve`, `DDGauge`, `PositionsTable`, `SignalRanking`

---

## ⚠️ RIESGOS Y MITIGACIONES

| Riesgo                                          | Mitigación                                                          |
| ----------------------------------------------- | ------------------------------------------------------------------- |
| `WebRequest()` requiere whitelist manual en MT5 | Documentar en onboarding + script PS1 de instalación                |
| MT5 corre client-side (sin push desde cloud)    | Bridge EA hace poll cada 5s (idéntico al timer actual)              |
| Múltiples instancias MT5 (H1 + H4)              | Cada Bridge EA registra con `accountId + magic_range` único         |
| Mantener lógica MQL5 ↔ Python sincronizada      | Python es la única fuente de verdad; MQL5 solo reporta estado       |
| Prop firm DD rules varían                       | Schema `risk_config` JSONB mapea cualquier firma (GOAT, FTMO, etc.) |
| Latencia en datos en tiempo real                | WebSocket from bridge → Redis pub-sub → dashboard                   |
