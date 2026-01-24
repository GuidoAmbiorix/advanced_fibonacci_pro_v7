# MT5 HTTP API Documentation

## Overview

The MT5 HTTP API exposes MetaTrader5 functionality via REST endpoints, allowing the Streamlit dashboard to connect from a separate Docker container.

## Architecture

```
┌─────────────────────┐         HTTP (8001)         ┌──────────────────┐
│   MT5 Container     │◄──────────────────────────┤  Streamlit       │
│                     │                             │  Dashboard       │
│  ┌───────────────┐  │                             │                  │
│  │ Wine/MT5      │  │                             │  Uses HTTP       │
│  └───────┬───────┘  │                             │  Connector       │
│          │          │                             │                  │
│  ┌───────▼───────┐  │                             │                  │
│  │ MetaTrader5   │  │                             │                  │
│  │ Python Lib    │  │                             │                  │
│  └───────┬───────┘  │                             │                  │
│          │          │                             │                  │
│  ┌───────▼───────┐  │                             │                  │
│  │ FastAPI       │  │                             │                  │
│  │ API Server    │◄─┼─────────────────────────────┤                  │
│  │ (Port 8001)   │  │                             │                  │
│  └───────────────┘  │                             │                  │
└─────────────────────┘                             └──────────────────┘
```

## Base URL

- Internal (Docker): `http://trading_mt5:8001`
- Via VPN: `http://10.13.13.20:8001`

## Endpoints

### Health Check

**GET** `/health`

Check if MT5 is connected and API is running.

**Response:**
```json
{
  "status": "healthy",
  "mt5_connected": true,
  "terminal": { ... }
}
```

---

### Account Information

**GET** `/account/info`

Get account information (balance, equity, margin, etc.)

**Response:**
```json
{
  "login": 123456,
  "balance": 10000.0,
  "equity": 10500.0,
  "margin": 500.0,
  "profit": 500.0,
  ...
}
```

---

### Positions

**GET** `/positions`

Get all open positions.

**Query Parameters:**
- `symbol` (optional): Filter by symbol

**Response:**
```json
[
  {
    "ticket": 123456,
    "symbol": "EURUSD",
    "type": 0,
    "volume": 0.1,
    "price_open": 1.0850,
    "sl": 1.0800,
    "tp": 1.0900,
    "profit": 50.0,
    ...
  }
]
```

---

### Orders

**GET** `/orders`

Get all pending orders.

**Query Parameters:**
- `symbol` (optional): Filter by symbol

---

### Deals History

**GET** `/history/deals`

Get deals history.

**Query Parameters:**
- `from_date` (optional): ISO format datetime
- `to_date` (optional): ISO format datetime
- `days` (optional): Number of days to look back (default: 30)

**Example:**
```
GET /history/deals?days=7
GET /history/deals?from_date=2026-01-01T00:00:00&to_date=2026-01-24T23:59:59
```

---

### Orders History

**GET** `/history/orders`

Get orders history.

**Query Parameters:** Same as deals history

---

### Symbols

**GET** `/symbols`

Get available symbols.

**Query Parameters:**
- `group` (optional): Filter by group pattern

**Response:**
```json
[
  {
    "name": "EURUSD",
    "bid": 1.0850,
    "ask": 1.0852,
    "spread": 20,
    ...
  }
]
```

---

**GET** `/symbols/{symbol}/info`

Get detailed symbol information.

**Example:** `GET /symbols/EURUSD/info`

---

**GET** `/symbols/{symbol}/tick`

Get last tick for symbol.

**Example:** `GET /symbols/EURUSD/tick`

**Response:**
```json
{
  "time": 1706112000,
  "bid": 1.0850,
  "ask": 1.0852,
  "last": 1.0851,
  "volume": 100
}
```

---

**GET** `/symbols/{symbol}/rates`

Get historical OHLCV data.

**Query Parameters:**
- `timeframe`: M1, M5, M15, M30, H1, H4, D1, W1, MN1 (default: H1)
- `count`: Number of bars (default: 100)

**Example:** `GET /symbols/EURUSD/rates?timeframe=H1&count=200`

**Response:**
```json
[
  {
    "time": "2026-01-24T10:00:00",
    "open": 1.0850,
    "high": 1.0860,
    "low": 1.0845,
    "close": 1.0855,
    "tick_volume": 1500,
    "spread": 20,
    "real_volume": 0
  },
  ...
]
```

---

### Terminal Info

**GET** `/terminal/info`

Get terminal information.

**Response:**
```json
{
  "community_account": false,
  "connected": true,
  "trade_allowed": true,
  "name": "MetaTrader 5",
  ...
}
```

---

### Version

**GET** `/version`

Get MT5 and API versions.

**Response:**
```json
{
  "mt5_version": [5, 0, 45],
  "api_version": "1.0.0"
}
```

---

## Error Handling

All endpoints return standard HTTP status codes:

- `200 OK`: Success
- `400 Bad Request`: Invalid parameters
- `404 Not Found`: Resource not found (e.g., symbol doesn't exist)
- `500 Internal Server Error`: MT5 error or API failure

Error response format:
```json
{
  "detail": "Error message here"
}
```

---

## Testing the API

### From the Dashboard Container
```bash
docker exec -it trading_dashboard curl http://trading_mt5:8001/health
```

### Via Wireguard VPN
```bash
curl http://10.13.13.20:8001/health
curl http://10.13.13.20:8001/account/info
curl http://10.13.13.20:8001/positions
curl "http://10.13.13.20:8001/symbols/EURUSD/rates?timeframe=H1&count=50"
```

### Interactive API Docs

FastAPI provides automatic interactive documentation:

- **Swagger UI**: http://10.13.13.20:8001/docs
- **ReDoc**: http://10.13.13.20:8001/redoc

---

## Python Client Example

```python
import requests

base_url = "http://trading_mt5:8001"

# Get account info
response = requests.get(f"{base_url}/account/info")
account = response.json()
print(f"Balance: {account['balance']}")

# Get positions
positions = requests.get(f"{base_url}/positions").json()
for pos in positions:
    print(f"{pos['symbol']}: {pos['profit']}")

# Get OHLCV data
rates = requests.get(
    f"{base_url}/symbols/EURUSD/rates",
    params={"timeframe": "H1", "count": 100}
).json()
```

---

## Security Notes

- API is not authenticated (relies on Docker network isolation)
- Only accessible from containers on the same Docker networks
- For production, consider adding API key authentication
- CORS enabled for dashboard access

---

## Troubleshooting

### API not responding
```bash
docker logs trading_mt5
docker exec -it trading_mt5 ps aux | grep python
```

### MT5 not initialized
Check if MT5 terminal is running and logged in via VNC (http://10.13.13.20:3000)

### Connection timeout
Verify both containers are on the same network:
```bash
docker network inspect mt5_trading_network
```
