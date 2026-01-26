# MT5 Trading System - Complete Docker Deployment

## 🎯 Overview

Complete trading system with:
- **MetaTrader 5** (Wine/Docker)
- **Portfolio Manager** (MQL5 EAs)
- **REST API Bridge** (Python/FastAPI)
- **Streamlit Dashboard** (Real-time monitoring)

## 🚀 Quick Start

```bash
# On VPS
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

## 📊 Architecture

```
┌──────────────────────────────────────────────────────┐
│ VPS (Docker Containers)                              │
│                                                      │
│  ┌────────────┐   ┌─────────────┐   ┌────────────┐ │
│  │    MT5     │──→│  API Bridge │──→│  Dashboard │ │
│  │   (Wine)   │   │  (FastAPI)  │   │ (Streamlit)│ │
│  │ Port: 3000 │   │ Port: 8001  │   │ Port: 8501 │ │
│  └────────────┘   └─────────────┘   └────────────┘ │
│                                                      │
└──────────────────────────────────────────────────────┘
                         ↓
                  CloudFlare Tunnel
                         ↓
              https://mt5.presumaster.com/
```

## 📁 Structure

```
mt5/
├── docker-compose.yml       # 3 services: mt5, api, dashboard
├── portafolio_manager/      # MQL5 Expert Advisors
├── mt5_api_bridge/          # REST API
│   ├── main.py
│   ├── Dockerfile
│   └── requirements.txt
├── streamlit_project/       # Dashboard
│   ├── app.py
│   ├── Dockerfile
│   └── ...
├── DEPLOYMENT_GUIDE.md      # Full deployment instructions
└── README.md                # This file
```

## 🔧 Services

### 1. MT5 Terminal (Port 3000)
- Runs in Wine
- Hosts Portfolio Governor & Symbol Engines
- VNC accessible for remote desktop

### 2. REST API Bridge (Port 8001)
- Exposes MT5 data via HTTP
- Endpoints: /health, /account, /globalvariables, /positions, etc.
- FastAPI with auto-generated docs at /docs

### 3. Streamlit Dashboard (Port 8501)
- Real-time EA monitoring
- Governor metrics
- System health checks
- Multi-account support

## 🌐 Access Points

- **Dashboard**: https://mt5.presumaster.com/
- **API Docs**: https://api.mt5.presumaster.com/docs
- **VNC (MT5)**: https://vnc.mt5.presumaster.com/

## 📖 Documentation

- **[DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)** - Complete deployment steps
- **[implementation_plan.md](../implementation_plan.md)** - Technical architecture

## 🛠️ Development

### Local Testing

```bash
# Build
docker-compose build

# Run
docker-compose up

# Rebuild specific service
docker-compose build dashboard
docker-compose up -d dashboard
```

### Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f mt5_api
```

## 🔄 Updates

```bash
# Pull changes
git pull

# Rebuild and restart
docker-compose up -d --build
```

## 📝 Environment Variables

Set in `docker-compose.yml`:

- `MT5_API_URL` - API endpoint (auto-configured)
- `USE_REMOTE_API` - Enable remote API mode
- `CUSTOM_USER` - VNC username
- `PASSWORD` - VNC password

## 🎯 Features

✅ Real-time EA status monitoring
✅ Portfolio Governor metrics
✅ GlobalVariables inspector
✅ System health dashboard
✅ Multi-account support
✅ Quick actions (emergency stop, pause, etc.)
✅ Alert system
✅ Performance analytics

## 🚨 Troubleshooting

See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for detailed troubleshooting.

Quick fixes:
```bash
# Restart all
docker-compose restart

# Check network
docker network inspect mt5_vpn_network

# Enter container
docker exec -it trading_dashboard bash
```

## 📊 Monitoring

Dashboard URL: **https://mt5.presumaster.com/**

Features:
- **EA Status Monitor** - See which EAs are running
- **Governor Dashboard** - DD, PF, Exposure metrics
- **GlobalVariables** - Inspect all GVs in real-time
- **System Health** - Component status checks

## 🔐 Security

- All services in private Docker network (10.13.13.0/24)
- Exposed only via CloudFlare Tunnel
- No direct port exposure to internet

## 📞 Support

Issues? Check:
1. Logs: `docker-compose logs -f`
2. Health: `curl http://localhost:8001/health`
3. Network: `docker-compose ps`

---

**Status**: ✅ Production Ready

**Last Updated**: 2026-01-26
