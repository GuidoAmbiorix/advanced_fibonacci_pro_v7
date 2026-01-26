# 🚀 Quick Start - VPS Deployment

## ⚡ TL;DR

```bash
# Stop existing
docker compose down

# Build and start
docker compose up -d --build

# Check status
docker compose ps
docker compose logs -f
```

## ✅ Success Check

```bash
# Test API
curl http://localhost:8001/health

# Test Dashboard
curl http://localhost:8501
```

## 📊 Access

- **Dashboard**: https://mt5.presumaster.com/
- **API Docs**: https://api.mt5.presumaster.com/docs  
- **VNC**: https://vnc.mt5.presumaster.com/

## 🔧 Common Commands

```bash
# View logs
docker compose logs -f mt5_api
docker compose logs -f dashboard

# Restart service
docker compose restart dashboard

# Stop all
docker compose down

# Rebuild specific service
docker compose build mt5_api
docker compose up -d mt5_api
```

## ⚠️ Important Notes

- Use `docker compose` (with space) NOT `docker-compose` (with dash)
- Your Docker version (29.1.5) has Compose as integrated plugin
- All services run in network: 10.13.13.0/24

## 📁 Project Structure

```
mt5/
├── docker-compose.yml       # Main config
├── mt5_api_bridge/          # REST API
├── streamlit_project/       # Dashboard
└── portafolio_manager/      # MQL5 EAs
```

## 🆘 Troubleshooting

**Containers won't start**:
```bash
docker compose logs [service-name]
docker compose down
docker compose up -d --build
```

**API not responding**:
```bash
docker compose exec dashboard ping mt5_api
docker compose restart mt5_api
```

**Dashboard shows errors**:
```bash
docker compose logs dashboard
docker compose restart dashboard
```

---

See **DEPLOYMENT_GUIDE.md** for detailed documentation.
