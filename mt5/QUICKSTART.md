# Quick Start Guide

## Overview

This setup includes:
1. **MT5 Container** (Wine + MT5 + Python API Server)
2. **Streamlit Dashboard** (Monitoring & Analytics)
3. **HTTP API Bridge** (Connects dashboard to MT5)

## Prerequisites
- Wireguard VPN container running on network `wireguard-vpn_vpn_network`
- Docker and Docker Compose installed

## Deploy in 3 Steps

### 1. Navigate to MT5 directory
```bash
cd /root/advanced_fibonacci_pro_v7/mt5
```

### 2. Configure environment (optional)
```bash
cd streamlit_project
nano .env  # Adjust settings if needed
cd ..
```

### 3. Launch services
```bash
docker-compose up -d --build
```

## Verify Deployment

```bash
# Check containers are running
docker ps | grep -E "trading_mt5|trading_dashboard"

# Check logs
docker-compose logs -f
```

## Access Services

### Through Wireguard VPN:
- **MT5 VNC**: http://10.13.13.20:3000 (user: trader, pass: trading)
- **Streamlit Dashboard**: http://10.13.13.21:8501

### Local Access (if on the server):
- **MT5 VNC**: http://localhost:3000
- **Streamlit Dashboard**: http://localhost:8501

## Network Topology

Both services are connected to:
- **trading_network**: Internal bridge for MT5 ↔ Dashboard communication
- **wireguard-vpn_vpn_network**: VPN network (10.13.13.0/24)

## What's Running

1. **trading_mt5**: Wine/MT5 container with Portfolio Manager EA
2. **trading_dashboard**: Streamlit dashboard for monitoring and analytics

## Troubleshooting

```bash
# Restart services
docker-compose restart

# Rebuild dashboard only
docker-compose up -d --build streamlit_dashboard

# Check network connectivity
docker exec -it trading_dashboard ping trading_mt5

# View dashboard logs
docker logs -f trading_dashboard
```

For detailed documentation, see [DEPLOYMENT.md](DEPLOYMENT.md)
