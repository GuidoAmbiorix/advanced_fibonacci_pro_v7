# 🚀 Deployment Guide - VPS Docker Setup

## 📦 What's Included

This setup includes **3 Docker containers**:

1. **trading_mt5** - MetaTrader 5 Terminal (Wine)
2. **mt5_api_bridge** - REST API to expose MT5 data
3. **trading_dashboard** - Streamlit Dashboard

## 🔧 Prerequisites

- Docker & Docker Compose installed on VPS
- CloudFlare Tunnel configured
- Ports: 3000 (VNC), 8001 (API), 8501 (Dashboard)

## 📂 File Structure

```
mt5/
├── docker-compose.yml          # Main Docker Compose file
├── portafolio_manager/          # Your MT5 Expert Advisors
│   ├── Portfolio_Governor.mq5
│   ├── Symbol_Engine.mq5
│   └── Include/...
├── mt5_api_bridge/              # NEW - REST API Bridge
│   ├── Dockerfile
│   ├── main.py
│   ├── requirements.txt
│   └── wait-for-mt5.sh
└── streamlit_project/           # Dashboard
    ├── Dockerfile
    ├── app.py
    ├── requirements.txt
    └── ...
```

## 🚀 Deployment Steps

### Step 1: Upload Files to VPS

```bash
# From your local machine
cd C:\Users\Ing Guido\Desktop\Proyectos\advanced_fibonacci_pro_v7\mt5
scp -r . user@your-vps:/path/to/deployment/
```

### Step 2: Connect to VPS

```bash
ssh user@your-vps
cd /path/to/deployment/
```

### Step 3: Stop Existing Containers (if any)

```bash
docker-compose down
```

### Step 4: Build and Start Everything

```bash
# Build all images
docker-compose build

# Start all services
docker-compose up -d
```

### Step 5: Check Status

```bash
# View logs
docker-compose logs -f

# Check if all containers are running
docker-compose ps

# Should show:
# trading_mt5          Up
# mt5_api_bridge       Up
# trading_dashboard    Up
```

### Step 6: Test Services

```bash
# Test API (from VPS)
curl http://localhost:8001/health

# Test Dashboard (from VPS)
curl http://localhost:8501
```

## 🌐 CloudFlare Tunnel Configuration

Update your CloudFlare Tunnel config to expose the dashboard:

```yaml
# /etc/cloudflared/config.yml
tunnel: your-tunnel-id
credentials-file: /path/to/credentials.json

ingress:
  # Main Dashboard
  - hostname: mt5.presumaster.com
    service: http://localhost:8501
  
  # API (optional - for external access)
  - hostname: api.mt5.presumaster.com
    service: http://localhost:8001
  
  # VNC (existing)
  - hostname: vnc.mt5.presumaster.com
    service: http://localhost:3000
  
  # Catch-all
  - service: http_status:404
```

Restart CloudFlare Tunnel:
```bash
sudo systemctl restart cloudflared
```

## 🔍 Accessing Services

After deployment:

- **Dashboard**: https://mt5.presumaster.com/
- **API Docs**: https://api.mt5.presumaster.com/docs (if exposed)
- **VNC (MT5)**: https://vnc.mt5.presumaster.com/

## 🛠️ Troubleshooting

### Container Logs

```bash
# All logs
docker-compose logs -f

# Specific container
docker-compose logs -f mt5_api
docker-compose logs -f dashboard
```

### Restart Services

```bash
# Restart single service
docker-compose restart mt5_api

# Restart all
docker-compose restart
```

### Rebuild After Changes

```bash
# Rebuild specific service
docker-compose build mt5_api
docker-compose up -d mt5_api

# Rebuild all
docker-compose build
docker-compose up -d
```

### Check MT5 API Connection

```bash
# From inside dashboard container
docker exec -it trading_dashboard bash
curl http://mt5_api:8001/health
```

## 📝 Quick Commands Cheat Sheet

```bash
# Start
docker-compose up -d

# Stop
docker-compose down

# Restart
docker-compose restart

# View logs
docker-compose logs -f

# Rebuild and restart
docker-compose up -d --build

# Remove everything (including volumes)
docker-compose down -v
```

## ✅ Success Indicators

Dashboard should show:
- ✅ MT5 Connected
- ✅ Account Info loaded
- ✅ EA Status Monitor working
- ✅ Governor metrics displayed

## 🔄 Updating the Code

```bash
# Pull latest changes
git pull

# Rebuild and restart
docker-compose up -d --build
```

## 🚨 Common Issues

**Issue**: Dashboard can't connect to API
```bash
# Check network
docker-compose exec dashboard ping mt5_api

# Check API logs
docker-compose logs mt5_api
```

**Issue**: MT5 not initializing
```bash
# Check MT5 container
docker-compose logs mt5

# Verify Wine is working
docker-compose exec mt5 wine --version
```

## 📊 Production Checklist

- [ ] All containers running (`docker-compose ps`)
- [ ] API health check passing (`curl localhost:8001/health`)
- [ ] Dashboard accessible via CloudFlare
- [ ] MT5 GlobalVariables visible in dashboard
- [ ] EA Status Monitor showing correct data
- [ ] No errors in logs

---

**Ready to go!** 🎉

Access your dashboard at: **https://mt5.presumaster.com/**
