# Quick Start Guide

Three easy ways to run the MT5 Trading Intelligence Platform.

---

## 🚀 Method 1: Batch File (Recommended for Windows)

**Double-click**: `run_dashboard.bat`

This script will:
- ✓ Check Python installation
- ✓ Create .env from template (if needed)
- ✓ Create required directories
- ✓ Install dependencies automatically
- ✓ Check if MT5 is running
- ✓ Launch the application

**First-time users**: The script will create `.env` file automatically. You may need to edit it to update the MT5 sets path.

---

## 🔷 Method 2: PowerShell (Advanced)

**Right-click** → **Run with PowerShell**: `run_dashboard.ps1`

Or from PowerShell terminal:
```powershell
.\run_dashboard.ps1
```

**Advanced Options**:
```powershell
# Skip configuration validation
.\run_dashboard.ps1 -SkipChecks

# Enable debug mode
.\run_dashboard.ps1 -Debug

# Run without opening browser
.\run_dashboard.ps1 -NoBrowser

# Combine options
.\run_dashboard.ps1 -Debug -NoBrowser
```

---

## 🖥️ Method 3: Manual (For Development)

```bash
# 1. Install dependencies (first time only)
pip install -r requirements.txt

# 2. Create .env file (first time only)
cp .env.example .env

# 3. Edit .env and update MT5_SETS_PATH

# 4. Run the application
streamlit run app.py
```

---

## 🔧 Troubleshooting

### If Application Won't Start

**Run the diagnostic tool**:
```
Double-click: check_system.bat
```

This will check:
- Python installation
- Required dependencies
- Configuration files
- Directory structure
- MT5 Terminal status
- Sets directory location
- Port availability
- Recent error logs

### Common Issues

| Problem | Solution |
|---------|----------|
| "Python not found" | Install Python 3.8+ from python.org |
| "Dependencies not installed" | Run: `pip install -r requirements.txt` |
| ".env not found" | Copy `.env.example` to `.env` |
| "MT5 not running" | Start MetaTrader 5 Terminal |
| "Sets directory not found" | Update `MT5_SETS_PATH` in `.env` |
| "Port 8501 already in use" | Close existing Streamlit instance |

---

## 📝 First-Time Setup

### Step 1: Install Python
- Download from: https://python.org/downloads/
- ✅ **Important**: Check "Add Python to PATH"

### Step 2: Run Launcher
- Double-click `run_dashboard.bat`
- It will auto-install dependencies

### Step 3: Configure
- If `.env` is created, edit it:
  ```env
  MT5_SETS_PATH=C:\path\to\your\sets
  ```
- Or keep the default path if it's correct

### Step 4: Start MT5
- Launch MetaTrader 5 Terminal
- Ensure it's logged in to your account

### Step 5: Launch Again
- Run `run_dashboard.bat` again
- Browser should open to http://localhost:8501

---

## 🎯 What Happens When You Launch

```
[1/6] Checking Python installation...        ← Verifies Python is available
[2/6] Checking configuration...              ← Creates .env if needed
[3/6] Creating required directories...       ← Creates logs/ and data/
[4/6] Checking dependencies...               ← Installs packages if needed
[5/6] Checking MetaTrader 5...              ← Checks if MT5 is running
[6/6] Launching application...               ← Starts Streamlit

Application starting on http://localhost:8501
```

---

## 🌐 Accessing the Application

Once launched, the application is available at:

- **Local**: http://localhost:8501
- **Network**: http://[your-ip]:8501

**Browser opens automatically** - If not, copy the URL from console.

---

## ⏹️ Stopping the Application

**In the console window**:
- Press `Ctrl+C`
- Or close the window

**From browser**:
- Just close the browser tab
- Application continues running until console is closed

---

## 📊 Application Tabs

Once running, explore these tabs:

1. **📊 Dashboard** - Account overview, equity curve, recent trades
2. **📈 Analytics** - Performance metrics and statistics
3. **🎨 Patterns** - Pattern-based performance analysis
4. **🏛️ Governor** - Portfolio selection and correlation analysis
5. **📉 Charts** - Symbol-specific charts with trade markers
6. **⏰ Time Analysis** - Performance by time/day/month
7. **📋 Trades** - Detailed trade history table

---

## 🔄 Updating Configuration

### While Application is Running:
1. Edit `.env` file
2. Save changes
3. Click "Rerun" in Streamlit (top-right)

### Common Settings to Adjust:

```env
# Logging level (DEBUG, INFO, WARNING, ERROR)
LOG_LEVEL=INFO

# Enable/disable caching
CACHE_ENABLED=true

# Correlation analysis
CORRELATION_BARS=100
CORRELATION_HIGH_THRESHOLD=0.75

# Scoring weights (must sum to 100)
SCORE_SESSION_ACTIVITY_MAX=20
SCORE_TREND_ALIGNMENT_MAX=25
SCORE_SPREAD_QUALITY_MAX=15
SCORE_VOLATILITY_MATCH_MAX=15
SCORE_HISTORICAL_PERF_MAX=25
```

---

## 📚 Additional Resources

- **Complete Documentation**: See `README.md`
- **Enhancement Details**: See `ENHANCEMENTS_SUMMARY.md`
- **Upgrade Instructions**: See `UPGRADE_GUIDE.md`
- **System Diagnostics**: Run `check_system.bat`

---

## 🆘 Getting Help

1. **Check Logs**:
   - `logs/mt5_platform.log` - General log
   - `logs/mt5_platform_errors.log` - Errors only

2. **Run Diagnostics**:
   - Double-click `check_system.bat`

3. **Enable Debug Logging**:
   - Set `LOG_LEVEL=DEBUG` in `.env`
   - Restart application

4. **Common Commands**:
   ```bash
   # Check Python
   python --version

   # Check installed packages
   pip list

   # Reinstall dependencies
   pip install -r requirements.txt --upgrade

   # Clear Streamlit cache
   streamlit cache clear
   ```

---

## ✨ Tips

- **First run takes longer** (installing dependencies)
- **Subsequent runs are instant** (everything cached)
- **Keep MT5 running** for real-time data
- **Check logs** if something seems wrong
- **Use dark theme** for better readability (default)

---

**Ready to Trade!** 📈
