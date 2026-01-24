# Service Access Guide

## Wireguard VPN Access (Primary Method)

Make sure you're connected to the Wireguard VPN, then access:

### MT5 Terminal (VNC)
```
URL: http://10.13.13.20:3000
Username: trader
Password: trading
VNC Password: trading
```

### Streamlit Trading Dashboard
```
URL: http://10.13.13.21:8501
```

### MT5 API Endpoint
```
URL: http://10.13.13.20:8001
```

---

## Local Access (Server Only)

If you're directly on the server (not through VPN):

### MT5 Terminal (VNC)
```
URL: http://localhost:3000
```

### Streamlit Trading Dashboard
```
URL: http://localhost:8501
```

---

## Network Details

- **Wireguard Network**: 10.13.13.0/24
- **Gateway**: 10.13.13.1
- **Wireguard Container**: 10.13.13.2
- **Portainer**: 10.13.13.10
- **MT5 Container**: 10.13.13.20 ← Fixed IP
- **Streamlit Dashboard**: 10.13.13.21 ← Fixed IP

---

## Quick Commands

```bash
# Check if services are running
docker ps | grep -E "trading_mt5|trading_dashboard"

# View logs
docker logs -f trading_mt5
docker logs -f trading_dashboard

# Restart services
cd /root/advanced_fibonacci_pro_v7/mt5
docker-compose restart

# Check network connectivity from dashboard to MT5
docker exec -it trading_dashboard ping 10.13.13.20
```
