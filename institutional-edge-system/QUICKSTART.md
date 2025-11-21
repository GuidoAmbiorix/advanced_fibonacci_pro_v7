# ⚡ Quick Start Guide - 5 Minutes to Running

## 🎯 Goal
Get the system running in 5 minutes for testing.

---

## ✅ Step 1: Install Python Dependencies (2 min)

```bash
cd institutional-edge-system

# Create virtual environment
python -m venv venv

# Activate it
# Windows:
venv\Scripts\activate
# Mac/Linux:
source venv/bin/activate

# Install requirements
pip install -r requirements.txt
```

---

## ✅ Step 2: Create .env File (1 min)

```bash
# Copy example
copy .env.example .env

# Edit .env and add MINIMUM required settings:
```

**Minimal .env for testing:**
```bash
# Database (SQLite for quick test)
DATABASE_URL=sqlite:///./test.db

# Security (generate with: openssl rand -hex 32)
SECRET_KEY=your-secret-key-here
JWT_SECRET_KEY=your-jwt-secret-here

# MT5 (Optional - leave empty for now)
MT5_LOGIN=
MT5_PASSWORD=
MT5_SERVER=
MT5_PATH=

# CORS
CORS_ORIGINS=http://localhost:3000,http://localhost:5173
```

---

## ✅ Step 3: Test the System (1 min)

```bash
# Run the test script
python test_system.py
```

You should see:
```
✅ ALL TESTS PASSED!
```

---

## ✅ Step 4: Start the Backend (30 sec)

```bash
cd backend/app
python main.py
```

You'll see:
```
INFO:     Starting Institutional Edge Pro API...
INFO:     API started successfully on 0.0.0.0:8000
INFO:     Uvicorn running on http://0.0.0.0:8000
```

---

## ✅ Step 5: Test the API (30 sec)

Open your browser to:
```
http://localhost:8000/docs
```

You'll see the **interactive API documentation**!

### Try These Endpoints:

1. **Health Check:**
   ```
   GET http://localhost:8000/health
   ```

2. **Analyze Market (with sample data):**
   ```
   GET http://localhost:8000/api/analysis/EURUSD/H1
   ```

   This will work even WITHOUT MT5 connected! It uses sample data.

---

## 🎉 You're Done!

The backend is now running. You can:

### Option A: Use the API Directly
- Open http://localhost:8000/docs
- Click "Try it out" on any endpoint
- Execute requests

### Option B: Connect Real MT5 (Optional)

1. **Install MT5** if not already installed
2. **Login to your broker account**
3. **Update .env:**
   ```bash
   MT5_LOGIN=your_account_number
   MT5_PASSWORD=your_password
   MT5_SERVER=YourBroker-Server
   MT5_PATH=C:\Program Files\MetaTrader 5\terminal64.exe
   ```
4. **Restart backend** (Ctrl+C, then `python main.py`)

Now API will use REAL market data!

### Option C: Build the Vue Dashboard

```bash
cd ../../frontend
npm install
npm run dev
```

Dashboard will run on http://localhost:5173

---

## 📝 Quick API Test with curl

```bash
# Get health status
curl http://localhost:8000/health

# Get market analysis
curl http://localhost:8000/api/analysis/EURUSD/H1

# If MT5 is connected:
curl http://localhost:8000/api/mt5/account
```

---

## 🐛 Common Issues

### "Module not found"
```bash
# Make sure virtual environment is activated
venv\Scripts\activate
pip install -r requirements.txt
```

### "Port already in use"
```bash
# Kill process on port 8000
# Windows:
netstat -ano | findstr :8000
taskkill /PID <PID> /F

# Or change port in main.py:
uvicorn.run(app, host="0.0.0.0", port=8001)
```

### "MT5 not connected"
- This is OK! System works without MT5 for testing
- It will use generated sample data
- Configure MT5 later when ready

---

## 🚀 Next Steps

1. ✅ System is running
2. ✅ API is accessible
3. **Now:**
   - Explore API endpoints at `/docs`
   - Test with different symbols/timeframes
   - Connect real MT5 account
   - Build/customize the Vue dashboard
   - Deploy to VPS for 24/7 operation

---

## 📞 Need Help?

Check the main [README.md](README.md) for:
- Full documentation
- Architecture details
- Deployment guide
- Troubleshooting

---

**Enjoy your professional trading system! 🎯**
