# V3 Trading System - Python Microservices

**Version:** 3.0.0-alpha
**Date:** January 29, 2026
**Status:** Phase 1 - Foundation

## 🏗️ Architecture

```
MT5 (MQL5) ←→ REST API ←→ Microservices (Python)
                 ↓              ↓
            Redis Cache    PostgreSQL DB
```

## 📦 Services

| Service | Port | Purpose | Status |
|---------|------|---------|--------|
| **API Gateway** | 8000 | REST API, routing | ✅ Implemented |
| **Redis** | 6379 | Real-time cache | ✅ Configured |
| **PostgreSQL** | 5432 | Historical data | ✅ Configured |
| **FinBERT** | - | Sentiment analysis | 🚧 In Progress |
| **HMM** | - | Regime detection | ⏳ Pending |
| **DRL** | - | Portfolio optimizer | ⏳ Pending |
| **OrderFlow** | - | Market microstructure | ⏳ Pending |

## 🚀 Quick Start

### Prerequisites

- Docker Desktop installed
- Python 3.11+ (for local development)
- MT5 installed with WebRequest enabled

### 1. Start Services

```bash
cd python_services
docker-compose up -d
```

### 2. Verify Health

```bash
curl http://localhost:8000/health
```

Expected response:
```json
{
  "status": "healthy",
  "services": {
    "api": true,
    "redis": true,
    "finbert": false,
    "hmm": false,
    "drl": false,
    "orderflow": false
  },
  "timestamp": "2026-01-29T14:30:00"
}
```

### 3. Enable WebRequest in MT5

Add to MT5 `Tools → Options → Expert Advisors`:
```
http://localhost:8000
```

### 4. Test from MT5

```mql5
#include <V3/PythonAPIClient.mqh>

CPythonAPIClient api;

int OnInit()
{
   if(!api.Init("http://localhost:8000"))
   {
      Print("Failed to connect to V3 API");
      return INIT_FAILED;
   }

   SentimentScore score;
   if(api.GetSentiment("EURUSD", score))
   {
      Print("EURUSD Sentiment: ", score.composite, " (confidence: ", score.confidence, ")");
   }

   return INIT_SUCCEEDED;
}
```

## 📊 API Endpoints

### Health Check
```http
GET /health
```

### Sentiment Analysis
```http
POST /sentiment
Content-Type: application/json

{
  "symbol": "EURUSD",
  "source": "auto"
}
```

Response:
```json
{
  "symbol": "EURUSD",
  "positive": 0.65,
  "negative": 0.25,
  "neutral": 0.10,
  "composite": 0.40,
  "confidence": 0.85,
  "timestamp": "2026-01-29T14:30:00"
}
```

### Regime Detection
```http
POST /regime
Content-Type: application/json

{
  "symbol": "EURUSD",
  "timeframe": "H1"
}
```

Response:
```json
{
  "symbol": "EURUSD",
  "regime": "REGIME_LOW_VOL_BULL",
  "probabilities": {
    "REGIME_LOW_VOL_BULL": 0.60,
    "REGIME_HIGH_VOL_BULL": 0.20,
    "REGIME_LOW_VOL_BEAR": 0.10,
    "REGIME_HIGH_VOL_BEAR": 0.05,
    "REGIME_SIDEWAYS_TIGHT": 0.03,
    "REGIME_SIDEWAYS_WIDE": 0.02,
    "REGIME_BREAKOUT": 0.00,
    "REGIME_CRISIS": 0.00
  },
  "confidence": 0.60,
  "timestamp": "2026-01-29T14:30:00"
}
```

### Order Flow Analysis
```http
POST /orderflow?symbol=EURUSD
```

Response:
```json
{
  "symbol": "EURUSD",
  "buy_volume": 1500.0,
  "sell_volume": 800.0,
  "imbalance": 0.30,
  "large_order_detected": true,
  "direction": 1,
  "confidence": 0.75,
  "timestamp": "2026-01-29T14:30:00"
}
```

## 🗄️ Database

### PostgreSQL Tables

- `trading.market_data` - OHLCV historical data
- `trading.trades` - Trade history
- `trading.sentiment_scores` - FinBERT sentiment
- `trading.regime_detections` - HMM regime classifications
- `trading.orderflow_data` - Order flow snapshots
- `trading.daily_performance` - Performance metrics
- `trading.news_events` - News headlines & events

### Connect to Database

```bash
docker exec -it v3_postgres psql -U v3_trader -d trading_v3
```

### Example Queries

```sql
-- Recent trades
SELECT * FROM trading.trades ORDER BY entry_time DESC LIMIT 10;

-- Win rate by symbol
SELECT * FROM trading.v_symbol_performance;

-- Daily performance
SELECT * FROM trading.v_recent_performance;
```

## 📈 Monitoring

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f api
docker-compose logs -f finbert
```

### Redis Monitoring

```bash
docker exec -it v3_redis redis-cli
> KEYS sentiment:*
> GET sentiment:EURUSD
> KEYS regime:*
```

## 🛠️ Development

### Local Development (without Docker)

```bash
# Install dependencies
pip install -r requirements.txt

# Run API locally
cd api
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Run Tests

```bash
pytest python_services/tests/
```

## 🔧 Configuration

### Environment Variables

Create `.env` file:
```env
REDIS_HOST=localhost
REDIS_PORT=6379
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=v3_trader
POSTGRES_PASSWORD=v3_secure_pass_2026
POSTGRES_DB=trading_v3
```

## 🚧 Next Steps (Phase 1)

- [x] Docker infrastructure
- [x] REST API gateway
- [x] MT5 API client
- [x] PostgreSQL schema
- [ ] FinBERT service implementation
- [ ] News RSS feed ingestion
- [ ] Real-time sentiment updates
- [ ] Basic dashboard UI

## 📝 Phase 2 Preview

- HMM Regime Detection
- Deep RL Portfolio Optimizer
- Walk-Forward Optimization
- Model training pipeline

## 🐛 Troubleshooting

### Docker services won't start

```bash
# Check Docker status
docker ps

# Restart all services
docker-compose down
docker-compose up -d
```

### MT5 can't connect to API

1. Check MT5 WebRequest settings (Tools → Options → Expert Advisors)
2. Add `http://localhost:8000` to allowed URLs
3. Verify API is running: `curl http://localhost:8000/health`

### Database connection errors

```bash
# Check PostgreSQL logs
docker-compose logs postgres

# Test connection
docker exec -it v3_postgres psql -U v3_trader -d trading_v3 -c "SELECT 1;"
```

## 📚 Documentation

- [V3 Roadmap](../V3_ROADMAP.md)
- [API Reference](docs/api.md) (TODO)
- [Architecture Guide](docs/architecture.md) (TODO)

## 📞 Support

For issues, check:
1. Docker logs: `docker-compose logs`
2. MT5 Expert Advisors logs
3. API health endpoint: `http://localhost:8000/health`

---

**Last Updated:** 2026-01-29
**Status:** Phase 1 - Foundation ✅ 60% Complete
