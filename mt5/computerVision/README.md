# CV Trading Agent - Complete System

## ✅ System Status: FULLY OPERATIONAL

All components are deployed and working:
- ✅ MT5 Bridge running on Windows host (port 5000)
- ✅ Dashboard running in Docker (port 8501)
- ✅ Auto-Trader running in Docker
- ✅ Database initialized with all tables

## 🚀 Quick Start Guide

### 1. Start MT5 Bridge (Already Running)
```powershell
cd bridge
python mt5_bridge.py
```

### 2. Access Dashboard
Open browser: **http://localhost:8501**

### 3. Train Your First Model
```powershell
python src/training/train_model.py --symbol EURUSD --timeframe H1
```

## 📊 Current System State

**MT5 Connection:** ✅ Connected  
**Account Balance:** $1000.00  
**Auto-Trading:** Disabled (for safety)  

## 🎯 Next Steps

1. **Train a model** using the training script
2. **View predictions** in the dashboard
3. **Configure risk parameters** in Trading Control
4. **Enable auto-trading** when ready

## 📝 Important Notes

- Auto-trading starts **disabled** for safety
- All trades are logged to the database
- Emergency stop button available in dashboard
- Default lot size: 0.01 (very conservative)

## 🛠️ Troubleshooting

If dashboard shows "Bridge Offline":
1. Ensure MT5 bridge is running
2. Check firewall settings
3. Rebuild Docker containers: `docker-compose up -d --build`

## 📁 Key Files

- `bridge/mt5_bridge.py` - MT5 communication service
- `dashboard/app.py` - Streamlit web interface  
- `src/trading/auto_trader.py` - Automated trading engine
- `src/training/train_model.py` - ML model training
- `data/cv_agent.db` - SQLite database

The system is ready for trading! 🎉
