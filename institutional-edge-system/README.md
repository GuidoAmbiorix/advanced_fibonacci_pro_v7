# 🚀 Institutional Edge PRO - Complete Trading System

A professional-grade, web-controlled automated trading system combining **Smart Money Concepts**, **Volume Profile Analysis**, and **AI-Enhanced Confluence Scoring**.

## 🏗️ Architecture

This is a **3-tier "Puppeteer" system**:

```
┌─────────────────────────────────────────────────────────────┐
│  📱 Vue 3 Dashboard (The Face)                             │
│  Beautiful web interface to control everything             │
│  • Start/Stop bots                                         │
│  • Monitor performance                                     │
│  • Adjust settings                                         │
│  • Real-time charts & alerts                              │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  │ REST API + WebSockets
                  │
┌─────────────────▼───────────────────────────────────────────┐
│  🧠 FastAPI Backend (The Brain)                            │
│  Python API server handling all logic                      │
│  • Trading Engine (SMC + Volume Profile)                   │
│  • Signal Generation                                       │
│  • Database Management                                     │
│  • User Authentication                                     │
│  • WebSocket real-time updates                            │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  │ Python MT5 API
                  │
┌─────────────────▼───────────────────────────────────────────┐
│  👋 MetaTrader 5 (The Hand)                                │
│  Executes actual trades with broker                        │
│  • Order execution                                         │
│  • Market data feed                                        │
│  • Position management                                     │
└─────────────────────────────────────────────────────────────┘
```

---

## ✨ Features

### 🎯 Smart Money Concepts
- ✅ **Order Blocks** - Institutional entry zones
- ✅ **Fair Value Gaps** - Imbalance areas
- ✅ **Break of Structure (BOS)** - Trend confirmation
- ✅ **Change of Character (CHOCH)** - Reversal detection
- ✅ **Liquidity Sweeps** - Stop hunt identification
- ✅ **Premium/Discount Zones** - Optimal entry areas

### 📊 Volume Profile Analysis
- ✅ **Point of Control (POC)** - Highest volume price level
- ✅ **Value Area High/Low** - 70% volume zone
- ✅ **Volume Nodes** - High/Low volume identification

### 🤖 AI-Enhanced Confluence System
- ✅ **Multi-Factor Scoring** (0-10 scale)
- ✅ **Score Breakdown** - Transparency on why each score
- ✅ **Dynamic Thresholds** - Adjustable minimum confluence

### 💼 Professional Features
- ✅ **Web Dashboard** - Control from anywhere
- ✅ **Multiple Bots** - Different strategies simultaneously
- ✅ **Risk Management** - Dynamic position sizing
- ✅ **Performance Metrics** - Win rate, P&L, drawdown
- ✅ **Real-time Alerts** - Telegram, Email, WebSocket

---

## 📦 Tech Stack

**Backend:**
- Python 3.10+
- FastAPI (REST API)
- SQLAlchemy + PostgreSQL (Database)
- MetaTrader5 Python API
- Redis (Caching)
- WebSockets (Real-time)

**Frontend:**
- Vue 3 + Vite
- TailwindCSS (Styling)
- Chart.js (Charts)
- Pinia (State Management)
- Axios (HTTP Client)

---

## 🚀 Quick Start Guide

### Prerequisites

1. **Python 3.10+** installed
2. **MetaTrader 5** installed and logged in
3. **PostgreSQL** installed (or use SQLite for testing)
4. **Node.js 18+** for frontend
5. **Redis** (optional, for caching)

---

### Step 1: Clone & Setup Backend

```bash
cd institutional-edge-system/backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r ../requirements.txt

# Create .env file
cp ../.env.example .env
```

### Step 2: Configure Environment

Edit `.env` file:

```bash
# IMPORTANT: Fill these in
MT5_LOGIN=your_mt5_account_number
MT5_PASSWORD=your_mt5_password
MT5_SERVER=your_broker_server
MT5_PATH=C:\Program Files\MetaTrader 5\terminal64.exe

# Database (Use SQLite for quick testing)
DATABASE_URL=postgresql+asyncpg://postgres:password@localhost:5432/institutional_edge
# OR use SQLite for testing:
# DATABASE_URL=sqlite:///./test.db

# Security
SECRET_KEY=your-super-secret-key-change-this
JWT_SECRET_KEY=another-super-secret-key-change-this
```

### Step 3: Initialize Database

```bash
# Run this from backend/app directory
python -c "from api.database import init_db; init_db()"
```

### Step 4: Start Backend Server

```bash
# From backend directory
cd app
python main.py

# OR with uvicorn:
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

You should see:
```
INFO:     Starting Institutional Edge Pro API...
INFO:     MT5 connected successfully
INFO:     API started successfully on 0.0.0.0:8000
INFO:     Uvicorn running on http://0.0.0.0:8000
```

**Test it:** Open http://localhost:8000/docs for interactive API docs

---

### Step 5: Setup Frontend

```bash
cd ../../frontend

# Install dependencies
npm install

# Start development server
npm run dev
```

Frontend will run on http://localhost:5173

---

## 🔧 API Endpoints

### Core Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | API status |
| GET | `/health` | Health check |
| GET | `/docs` | Interactive API docs |

### MT5 Operations

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/mt5/account` | Get account info |
| GET | `/api/mt5/price/{symbol}` | Get current price |
| GET | `/api/mt5/positions` | Get open positions |

### Trading Analysis

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/analysis/{symbol}/{timeframe}` | Analyze market & get signals |

Example:
```bash
curl http://localhost:8000/api/analysis/EURUSD/H1
```

Response:
```json
{
  "timestamp": "2024-01-15T10:30:00",
  "current_price": 1.0850,
  "trend": "BULLISH",
  "active_order_blocks": 3,
  "active_fvgs": 2,
  "poc_level": 1.0845,
  "bull_confluence_score": 8,
  "bear_confluence_score": 3,
  "bull_score_breakdown": {
    "Order Block": 2,
    "FVG": 2,
    "Trend": 2,
    "Discount Zone": 2
  },
  "signals": [
    {
      "signal_type": "BUY",
      "entry_price": 1.0850,
      "stop_loss": 1.0820,
      "take_profit_1": 1.0880,
      "take_profit_2": 1.0910,
      "confluence_score": 8,
      "risk_reward_ratio": 2.0
    }
  ]
}
```

### Bot Control

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/bot/start` | Start trading bot |
| POST | `/api/bot/stop` | Stop trading bot |
| GET | `/api/bot/status/{id}` | Get bot status |

### Trades

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/trades` | Get trade history |
| POST | `/api/trades/open` | Open new trade |

### WebSocket

```javascript
// Connect to WebSocket
const ws = new WebSocket('ws://localhost:8000/ws');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Update:', data);
};
```

---

## 📊 Trading Engine Overview

### How It Works

1. **Data Collection**: MT5 provides OHLCV data for analysis
2. **Market Structure**: Detects swing points, trend direction
3. **Pattern Recognition**: Identifies OBs, FVGs, liquidity sweeps
4. **Volume Profile**: Calculates POC, Value Area
5. **Confluence Scoring**: Rates setup quality (0-10)
6. **Signal Generation**: Creates trade signals when score ≥ threshold
7. **Execution**: Opens trades via MT5 API with proper risk management

### Confluence Scoring Breakdown

| Factor | Points | Description |
|--------|--------|-------------|
| Order Block Alignment | +2 | Price at valid OB zone |
| Fair Value Gap | +2 | Price in FVG |
| Market Structure | +2 | Aligned with trend |
| Premium/Discount Zone | +2 | Optimal entry zone |
| Liquidity Sweep | +2 | Recent sweep detected |
| Near POC | +1 | Price near volume POC |
| Volume Confirmation | +1 | High volume on signal bar |

**Max Score**: 10 points
**Default Threshold**: 6 points

---

## 🎨 Frontend Dashboard Features (To Be Built)

```
📊 Dashboard Home
├── Real-time P&L Chart
├── Active Bots Status
├── Open Positions Table
└── Today's Performance Metrics

⚙️ Bot Configuration
├── Create New Bot
├── Edit Settings (Risk %, Symbol, Timeframe)
├── Start/Stop Buttons
└── Parameter Tuning

📈 Trading Signals
├── Live Signal Feed
├── Confluence Score Display
├── Entry/Exit Levels
└── One-Click Trade Execution

📜 Trade History
├── All Trades Table
├── Filter by Status/Symbol
├── P&L Analysis
└── Performance Charts

🔔 Alerts & Notifications
├── Telegram Integration
├── Email Alerts
└── Browser Push Notifications
```

---

## 🔐 Security Best Practices

1. **Never commit `.env` file** - Contains sensitive credentials
2. **Use strong SECRET_KEY** - Generate with `openssl rand -hex 32`
3. **Change default passwords** - For database, MT5
4. **Enable HTTPS** - In production
5. **Encrypt MT5 password** - In database
6. **Use JWT tokens** - For authentication
7. **Rate limiting** - Prevent API abuse

---

## 🚀 Deployment (Production)

### Using Docker

```bash
# Build backend
cd backend
docker build -t institutional-edge-backend .

# Run with docker-compose
docker-compose up -d
```

### Manual Deployment

1. **VPS Setup** (DigitalOcean, AWS, etc.)
2. **Install dependencies**
3. **Setup PostgreSQL**
4. **Configure Nginx** (reverse proxy)
5. **Setup SSL** (Let's Encrypt)
6. **Run with supervisor/systemd**

---

## 📈 Roadmap

- [x] Core Trading Engine (SMC + VP)
- [x] MT5 Integration
- [x] FastAPI Backend
- [x] Database Models
- [x] REST API Endpoints
- [x] WebSocket Support
- [ ] Vue 3 Dashboard UI
- [ ] User Authentication
- [ ] Multi-user Support
- [ ] Telegram Bot Integration
- [ ] Backtesting Engine
- [ ] Strategy Optimizer
- [ ] Mobile App (React Native)
- [ ] Docker Deployment
- [ ] Cloud Hosting

---

## 🐛 Troubleshooting

### MT5 Connection Issues

```
Error: MT5 initialize() failed
```

**Solutions:**
1. Ensure MT5 is installed and running
2. Check MT5_PATH in .env is correct
3. Verify MT5 login credentials
4. Check broker allows API access

### Database Connection Error

```
Error: Could not connect to database
```

**Solutions:**
1. Ensure PostgreSQL is running
2. Check DATABASE_URL in .env
3. Verify database exists: `createdb institutional_edge`
4. Check credentials

### Import Errors

```
ModuleNotFoundError: No module named 'MetaTrader5'
```

**Solutions:**
1. Activate virtual environment
2. Run `pip install -r requirements.txt`
3. Ensure Python 3.10+ is being used

---

## 📞 Support

For issues, questions, or feature requests:
- GitHub Issues: [Create issue](https://github.com/your-repo/issues)
- Email: support@institutionaledge.pro

---

## 📄 License

This project is licensed under the MIT License.

---

## 🙏 Acknowledgments

- TradingView Pine Script Community
- MetaTrader 5 Python API
- FastAPI Framework
- Vue.js Team

---

**Built with ❤️ for serious traders**
