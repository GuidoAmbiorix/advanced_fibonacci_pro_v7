# 🚀 SIMPLIFIED DEPLOYMENT - Single Container

## ⚠️ CHANGE: Single Container Strategy

**Previous**: 3 separate containers (didn't work - MetaTrader5 package is Windows-only)

**New**: **All-in-one** container running:
1. MT5 Terminal (Wine)
2. FastAPI Bridge (Python)
3. Streamlit Dashboard (Python)

All inside the **same Wine container** where MT5 is installed.

---

## 🎯 Architecture

```
┌────────────────────────────────────────────────┐
│  Single Docker Container (Wine/Ubuntu)         │
│                                                │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐  │
│  │   MT5    │──→│    API   │──→│ Dashboard│  │
│  │  (Wine)  │   │(Python)  │   │(Streamlit)  │
│  │          │   │          │   │          │  │
│  │Port: 3000│   │Port: 8001│   │Port: 8501│  │
│  └──────────┘   └──────────┘   └──────────┘  │
│                                                │
│  10.13.13.20                                   │
└────────────────────────────────────────────────┘
             ↓
      CloudFlare Tunnel
             ↓
  https://mt5.presumaster.com/
```

---

## 🚀 DEPLOYMENT (Super Simple)

### 1. Stop Current Container

```bash
docker compose down
```

### 2. Make Script Executable

```bash
chmod +x start_services.sh
```

### 3. Start Everything

```bash
docker compose up -d
```

### 4. Check Logs

```bash
docker compose logs -f
```

You should see:
```
Starting MT5 Trading System...
Waiting for Wine/MT5 to initialize...
Installing Python packages...
Starting MT5 API Bridge on port 8001...
Starting Streamlit Dashboard on port 8501...
✅ All services started!
```

### 5. Verify Services

```bash
# Test API
curl http://localhost:8001/health

# Test Dashboard
curl http://localhost:8501

# Enter container to debug
docker compose exec mt5 bash
```

---

## 🌐 Access Points

- **Dashboard**: https://mt5.presumaster.com/ (via CloudFlare)
- **API Docs**: http://your-vps-ip:8001/docs
- **VNC**: https://vnc.mt5.presumaster.com/

---

## 🔧 File Structure

```
mt5/
├── docker-compose.yml       # Single service config
├── start_services.sh        # Startup script (runs all 3 services)
├── mt5_api_bridge/
│   └── main.py              # FastAPI server
└── streamlit_project/
    └── app.py               # Dashboard
```

---

## 📝 Commands

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Restart
docker compose restart

# View logs
docker compose logs -f

# Enter container
docker compose exec mt5 bash

# Check processes inside container
docker compose exec mt5 ps aux

# Rebuild and restart
docker compose up -d --build --force-recreate
```

---

## 🐛 Troubleshooting

### Container fails to start

```bash
# Check logs
docker compose logs

# Try rebuilding
docker compose down
docker compose up -d --force-recreate
```

### Services not responding

```bash
# Enter container
docker compose exec mt5 bash

# Check API
curl http://localhost:8001/health

# Check Dashboard
curl http://localhost:8501

# View service logs
cat /tmp/api.log
cat /tmp/dashboard.log

# Restart services manually
cd /app/mt5_api_bridge
python3 main.py &

cd /app/streamlit_project
streamlit run app.py --server.port=8501 --server.address=0.0.0.0 &
```

### MT5 not connecting

```bash
# Enter container
docker compose exec mt5 bash

# Check Wine processes
ps aux | grep wine

# Restart Wine
killall wine
/init &
```

---

## ✅ Success Indicators

1. **Container running**: `docker compose ps` shows "Up"
2. **API responding**: `curl localhost:8001/health` returns JSON
3. **Dashboard loading**: `curl localhost:8501` returns HTML
4. **Logs clean**: No errors in `docker compose logs`

---

## 🔄 Updates

```bash
cd /path/to/mt5
git pull
docker compose restart
```

---

## 📊 CloudFlare Tunnel Config

```yaml
# /etc/cloudflared/config.yml
ingress:
  - hostname: mt5.presumaster.com
    service: http://localhost:8501      # Streamlit Dashboard
  
  - hostname: vnc.mt5.presumaster.com
    service: http://localhost:3000      # VNC
  
  - hostname: api.mt5.presumaster.com   # Optional
    service: http://localhost:8001      # API
  
  - service: http_status:404
```

Restart tunnel:
```bash
sudo systemctl restart cloudflared
```

---

## 🎯 Why This Works

**Problem**: MetaTrader5 Python package only works on Windows with MT5 installed

**Solution**: Run Python API **inside the Wine container** where MT5 is actually installed

The Wine container has:
- MT5 Terminal (Windows app via Wine)
- Python 3 (Linux)
- MetaTrader5 package can access MT5 via Wine

---

## 🚨 Important Notes

- All 3 services run in **same container**
- Uses Wine's MT5 installation
- Simpler than multi-container setup
- Less resource usage
- Easier to debug

---

**Ready!** Just run `docker compose up -d` and access https://mt5.presumaster.com/
