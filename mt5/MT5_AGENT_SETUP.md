# MT5 Portfolio Manager Agent - Setup Guide

## Overview

Your MT5 container is configured with:
- **Memory**: 4GB RAM allocation
- **Agent**: Portfolio Manager (fully mounted and ready)
- **VPN Access**: 10.13.13.20:3000
- **Configuration**: 4 currency pair presets (EURUSD, GBPUSD, EURGBP, XAUUSD)

---

## Container Status

### Check if Running
```bash
docker ps | grep trading_mt5
```

### View Logs
```bash
docker logs trading_mt5
```

### Resource Usage
```bash
docker stats trading_mt5
```

---

## Accessing MT5 Terminal

### Via Wireguard VPN (Recommended)
1. Connect to your Wireguard VPN
2. Open browser: **http://10.13.13.20:3000**
3. Login credentials:
   - **User**: trader
   - **Password**: trading

### VNC Settings
- Port: 3000
- Protocol: HTTP (web-based VNC)
- No additional VNC client needed

---

## Loading the Portfolio Manager Agent

### Step 1: Login to MT5 Account
1. Access VNC at http://10.13.13.20:3000
2. Open MetaTrader 5 terminal
3. File → Login to Trade Account
4. Enter your broker credentials

### Step 2: Enable Expert Advisors
1. Go to: **Tools → Options**
2. Navigate to: **Expert Advisors** tab
3. Enable:
   - ☑ Allow automated trading
   - ☑ Allow DLL imports
   - ☑ Allow WebRequest for listed URL (add your broker's URL if needed)
4. Click **OK**

### Step 3: Load the Agent on Charts

#### For Each Currency Pair (EURUSD, GBPUSD, EURGBP, XAUUSD):

1. **Open Chart**:
   - File → New Chart → Select symbol (e.g., EURUSD)
   - Set your preferred timeframe

2. **Attach Expert Advisor**:
   - In Navigator panel (Ctrl+N if hidden)
   - Expand: Expert Advisors → portafolio_manager
   - Drag **Portfolio_Governor** onto the chart

3. **Load Configuration**:
   - In the EA settings dialog:
   - Click **Load** button (bottom)
   - Navigate to: `MQL5/Experts/portafolio_manager/sets/`
   - Select the appropriate .set file:
     - `eurusd.set` for EURUSD chart
     - `gbpusd.set` for GBPUSD chart
     - `eurgbp.set` for EURGBP chart
     - `xauusd.set` for XAUUSD chart
   - Click **Open**

4. **Enable Live Trading**:
   - In the **Common** tab:
   - ☑ Allow live trading
   - ☑ Allow DLL imports
   - Click **OK**

5. **Verify Agent is Running**:
   - Look for a **smiley face icon** 😊 in the top-right corner of the chart
   - Experts tab should show initialization messages
   - No errors should appear

### Step 4: Arrange Your Workspace

1. **Tile Windows** for 4 charts:
   - Window → Tile Vertically (or Tile Horizontally)
   - Or drag charts to arrange manually

2. **Save Template** (recommended):
   - File → Save Template
   - Name it: "Portfolio_Manager_4_Pairs"
   - Next time: File → Open Offline → Select template

---

## Agent Configuration Files Location

Inside container:
```
/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/portafolio_manager/
├── Portfolio_Governor.mq5    # Main Expert Advisor
├── Symbol_Engine.mq5/.ex5    # Trading engine
├── Include/                   # Libraries and dependencies
│   ├── Adaptive/
│   ├── Config/
│   ├── KillzoneOptimizer.mqh
│   ├── NewsFilter.mqh
│   └── KellyPositionSizer.mqh
└── sets/                      # Configuration presets
    ├── eurusd.set
    ├── gbpusd.set
    ├── eurgbp.set
    └── xauusd.set
```

On host (for editing):
```
/root/advanced_fibonacci_pro_v7/mt5/portafolio_manager/
```

---

## Monitoring the Agent

### MT5 Terminal Tabs:

1. **Experts Tab**:
   - Shows EA initialization and runtime logs
   - Any errors will appear here

2. **Journal Tab**:
   - Shows connection status
   - Server messages

3. **Toolbox → Trade**:
   - View open positions
   - Pending orders

4. **Toolbox → History**:
   - View closed trades
   - Performance statistics

### Key Indicators Agent is Working:

✅ Smiley face icon on chart
✅ No errors in Experts tab
✅ Positions appear when signals trigger
✅ Logs show "Initialized successfully" message

---

## Memory Configuration

The container is allocated **4GB RAM** to handle:
- MT5 Terminal
- Wine environment
- 4 concurrent charts with Portfolio Manager EA
- Historical data buffering

### Check Memory Usage:
```bash
docker stats trading_mt5
```

If you experience performance issues:
- Reduce number of active charts
- Increase memory limit in docker-compose.yml
- Close unused MT5 windows

---

## Modifying Agent Configuration

### To Change EA Settings:

1. **On Running Charts**:
   - Right-click chart → Expert Advisors → Properties
   - Modify parameters
   - Click OK (EA will reload)

2. **In .set Files** (on host machine):
   ```bash
   cd /root/advanced_fibonacci_pro_v7/mt5/portafolio_manager/sets
   nano eurusd.set  # or other set file
   ```
   - Save changes
   - In MT5: Load the updated .set file again

3. **Restart Container** (if needed):
   ```bash
   docker compose restart trading_mt5
   ```

---

## Troubleshooting

### Agent Not Loading

**Issue**: "Expert advisor is not allowed to trade"
- **Solution**: Enable automated trading in Tools → Options → Expert Advisors

**Issue**: "DLL imports are not allowed"
- **Solution**: Check "Allow DLL imports" in EA properties → Common tab

**Issue**: ".set file not found"
- **Solution**: Verify mount point:
  ```bash
  docker exec trading_mt5 ls "/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/portafolio_manager/sets/"
  ```

### Performance Issues

**Symptoms**: Slow chart rendering, delayed signals

**Solutions**:
1. Check memory usage:
   ```bash
   docker stats trading_mt5
   ```

2. Reduce chart complexity:
   - Disable unnecessary indicators
   - Reduce chart history loaded

3. Increase container memory in docker-compose.yml:
   ```yaml
   deploy:
     resources:
       limits:
         memory: 6G  # Increase from 4G to 6G
   ```
   Then restart: `docker compose up -d`

### Connection Lost

**Issue**: VNC shows "Connection lost"
- **Solution**: Container restarted, refresh browser at http://10.13.13.20:3000

**Issue**: Can't access via VPN
- **Solution**:
  ```bash
  docker network inspect wireguard-vpn_vpn_network | grep trading_mt5
  # Verify IP is 10.13.13.20
  ```

---

## Backup & Persistence

### Data Persistence

All MT5 data is stored in Docker volume: `mt5_mt5_config`

This includes:
- Account credentials
- Chart templates
- EA settings
- Historical data

### Backup MT5 Configuration

```bash
# Create backup
docker run --rm -v mt5_mt5_config:/source -v $(pwd):/backup \
  alpine tar czf /backup/mt5_backup_$(date +%Y%m%d).tar.gz -C /source .

# Restore backup
docker run --rm -v mt5_mt5_config:/target -v $(pwd):/backup \
  alpine sh -c "cd /target && tar xzf /backup/mt5_backup_YYYYMMDD.tar.gz"
```

---

## Quick Commands Reference

```bash
# Start MT5 container
docker compose up -d

# Stop MT5 container
docker compose down

# Restart MT5 container
docker compose restart trading_mt5

# View real-time logs
docker logs -f trading_mt5

# Access container shell
docker exec -it trading_mt5 bash

# Check agent files
docker exec trading_mt5 ls -la "/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/portafolio_manager/"

# Resource usage
docker stats trading_mt5

# Check IP address
docker inspect trading_mt5 | grep IPAddress
```

---

## Next Steps

1. ✅ Access MT5: http://10.13.13.20:3000
2. ✅ Login to your broker account
3. ✅ Enable automated trading
4. ✅ Load Portfolio_Governor on 4 charts
5. ✅ Apply corresponding .set files
6. ✅ Monitor performance

For dashboard monitoring from your Windows PC, see: `streamlit_project/README.md`

---

## Support

**Container Issues**: Check logs with `docker logs trading_mt5`
**EA Issues**: Check MT5 Experts tab for error messages
**Network Issues**: Verify Wireguard VPN is connected
**Memory Issues**: Monitor with `docker stats`
