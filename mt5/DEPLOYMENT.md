# MT5 Trading Platform Deployment Guide

## Overview
This deployment sets up a complete MT5 trading platform with:
- **MT5 Terminal**: Wine-based MT5 container with VNC access
- **Portfolio Manager**: MQL5 expert advisor for portfolio management
- **Streamlit Dashboard**: Real-time monitoring and analytics dashboard
- **Wireguard VPN**: All services connected through VPN network

## Architecture

```
┌───────────────────────────────────────────────────┐
│      Wireguard VPN Network (10.13.13.0/24)        │
│                                                   │
│  ┌──────────────────┐   ┌──────────────────────┐ │
│  │  MT5 (Wine)      │◄──┤  Streamlit Dashboard │ │
│  │  10.13.13.20     │   │  10.13.13.21         │ │
│  │  Port: 3000      │   │  Port: 8501          │ │
│  │  Port: 8001      │   │                      │ │
│  └──────────────────┘   └──────────────────────┘ │
│                                                   │
└───────────────────────────────────────────────────┘
```

## Prerequisites

1. Docker and Docker Compose installed
2. Wireguard VPN container running (network: `wireguard-vpn_vpn_network`)
3. SSH access to GitHub configured

## Directory Structure

```
mt5/
├── docker-compose.yml          # Main orchestration file
├── portafolio_manager/         # MT5 Expert Advisor
│   ├── Portfolio_Governor.mq5
│   ├── Symbol_Engine.mq5
│   └── sets/                   # EA configuration files
└── streamlit_project/          # Dashboard application
    ├── Dockerfile
    ├── app.py
    ├── requirements.txt
    ├── .env                    # Environment configuration
    ├── components/
    └── src/
```

## Deployment Steps

### 1. Clone Repository
```bash
git clone -b mt5-like git@github.com:GuidoAmbiorix/advanced_fibonacci_pro_v7.git
cd advanced_fibonacci_pro_v7/mt5
```

### 2. Configure Environment
```bash
cd streamlit_project
# Edit .env file with your settings
nano .env
```

### 3. Build and Start Services
```bash
cd ..
docker-compose up -d --build
```

### 4. Verify Deployment
```bash
# Check running containers
docker ps

# Check logs
docker logs trading_mt5
docker logs trading_dashboard

# Test connectivity
curl http://localhost:8501
```

## Service Access

### Through Wireguard VPN (Recommended):
- **MT5 VNC**: http://10.13.13.20:3000 (user: trader, password: trading)
- **Streamlit Dashboard**: http://10.13.13.21:8501
- **MT5 API**: http://10.13.13.20:8001

### Local Access (on server):
- **MT5 VNC**: http://localhost:3000
- **Streamlit Dashboard**: http://localhost:8501
- **MT5 API**: http://localhost:8001

## Network Configuration

Both services are connected to two networks:
- `trading_network`: Internal communication between MT5 and Dashboard
- `wireguard-vpn_vpn_network`: External VPN network (10.13.13.0/24)
  - MT5 Container: **10.13.13.20**
  - Streamlit Dashboard: **10.13.13.21**

## Managing the Deployment

### Start Services
```bash
docker-compose up -d
```

### Stop Services
```bash
docker-compose down
```

### View Logs
```bash
docker-compose logs -f
# Or for specific service:
docker-compose logs -f streamlit_dashboard
```

### Rebuild Dashboard
```bash
docker-compose up -d --build streamlit_dashboard
```

### Update Code
```bash
git pull origin mt5-like
docker-compose up -d --build
```

## Portfolio Manager Setup

1. Access MT5 VNC at http://localhost:3000
2. Navigate to: Tools → Options → Expert Advisors
3. Enable: "Allow automated trading"
4. Load the Portfolio_Governor EA from `/mt5/MQL5/Experts/portafolio_manager/`
5. Apply the .set file from the sets/ directory

## Troubleshooting

### Dashboard Can't Connect to MT5
```bash
# Check if MT5 is running
docker exec -it trading_mt5 ps aux | grep terminal

# Check network connectivity
docker exec -it trading_dashboard ping trading_mt5
```

### MT5 Expert Advisor Not Loading
```bash
# Check EA files are mounted
docker exec -it trading_mt5 ls -la /mt5/MQL5/Experts/portafolio_manager/
```

### VPN Connectivity Issues
```bash
# Verify Wireguard network
docker network inspect wireguard-vpn_vpn_network

# Check container is connected
docker inspect trading_dashboard | grep -A 10 Networks
```

## Pushing Changes

After making changes to the streamlit dashboard:

```bash
cd streamlit_project
# Test changes locally first
docker-compose up -d --build streamlit_dashboard

# Commit and push
git add .
git commit -m "Update: description of changes"
git push origin mt5-like
```

## Security Notes

- The `.env` file is not committed (in .gitignore)
- Default passwords should be changed in production
- VNC access should be restricted via firewall rules
- Consider using secrets management for production deployments

## Maintenance

### Backup Data
```bash
# Backup MT5 configuration
docker cp trading_mt5:/config ./backups/mt5_config_$(date +%Y%m%d)

# Backup Dashboard data
docker cp trading_dashboard:/app/data ./backups/dashboard_data_$(date +%Y%m%d)
```

### Update Images
```bash
docker-compose pull
docker-compose up -d
```

## Support

For issues and questions:
- Check logs: `docker-compose logs`
- Review configuration: `.env` and `docker-compose.yml`
- Verify network: `docker network inspect wireguard-vpn_vpn_network`
