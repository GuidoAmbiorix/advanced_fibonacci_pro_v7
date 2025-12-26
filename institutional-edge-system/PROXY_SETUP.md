# Institutional Edge Pro - Reverse Proxy Setup Guide

This guide explains how to set up and use the nginx reverse proxy for managing multiple trading bot instances.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Nginx Reverse Proxy                      │
│                   http://localhost:80                        │
└───────┬─────────────────────────────────────────────────────┘
        │
        ├─── /                          → Orchestrator UI (:9000)
        ├─── /api/orchestrator/*        → Orchestrator API (:9001)
        │
        ├─── /instance/1/*              → Instance 1 Frontend (:80)
        ├─── /instance/1/api/*          → Instance 1 Backend (:8000)
        ├─── /instance/1/socket.io/*    → Instance 1 WebSocket
        │
        ├─── /instance/2/*              → Instance 2 Frontend (:81)
        ├─── /instance/2/api/*          → Instance 2 Backend (:8002)
        ├─── /instance/2/socket.io/*    → Instance 2 WebSocket
        │
        └─── /instance/N/*              → Instance N Frontend
             /instance/N/api/*          → Instance N Backend
             /instance/N/socket.io/*    → Instance N WebSocket
```

## Benefits

✅ **Single Origin** - All services accessible from `http://localhost`
✅ **No CORS Issues** - All requests go through the same domain
✅ **Clean URLs** - `/instance/1/api` instead of `localhost:8000`
✅ **WebSocket Support** - Full Socket.IO support with proxy routing
✅ **Production Ready** - Easy to deploy with SSL/TLS
✅ **Scalable** - Add unlimited instances without CORS configuration

## Quick Start

### 1. Start the Nginx Proxy

```bash
# From project root
docker-compose -f docker-compose.proxy.yml up -d
```

### 2. Verify Proxy is Running

```bash
# Check nginx health
curl http://localhost/health
# Should return: healthy
```

### 3. Start an Instance

```bash
# Start instance 1
cd instances/instance-1
docker-compose up -d

# Access through proxy:
# Frontend: http://localhost/instance/1
# API: http://localhost/instance/1/api
```

## Port Allocation Strategy

Each instance uses a consistent port pattern:

| Instance | VNC Port | RPyC Port | API Port | Web Port | Proxy URL |
|----------|----------|-----------|----------|----------|-----------|
| 1        | 3000     | 8001      | 8000     | 80       | /instance/1 |
| 2        | 3001     | 8003      | 8002     | 81       | /instance/2 |
| 3        | 3002     | 8005      | 8004     | 82       | /instance/3 |
| N        | 3000+(N-1) | 8001+2*(N-1) | 8000+2*(N-1) | 80+(N-1) | /instance/N |

## Configuration

### Backend CORS Configuration

Each instance backend is configured to only allow requests from the proxy:

```env
# backend/.env
CORS_ORIGINS=http://localhost,http://127.0.0.1,http://localhost:80
```

### Frontend Environment Variables

Each instance frontend needs these environment variables:

```env
# frontend/.env (for instance 1)
VITE_INSTANCE_NUMBER=1
VITE_API_BASE_URL=/instance/1/api
VITE_SOCKET_URL=/instance/1
VITE_INSTANCE_NAME=Instance 1
```

## Using the Instance Manager

The orchestrator provides a Python script to manage instances:

### Install Dependencies

```bash
cd orchestrator
pip install -r requirements.txt
```

### Create an Instance

```python
from instance_manager import InstanceManager, InstanceConfig

manager = InstanceManager(base_dir=".")

# Create instance 1
config = InstanceConfig(
    instance_number=1,
    instance_name="main",
    mt5_login="YOUR_LOGIN",
    mt5_password="YOUR_PASSWORD",
    mt5_server="YOUR_SERVER"
)

manager.create_instance(config)
```

### List Instances

```python
instances = manager.list_instances()
for inst in instances:
    print(f"Instance {inst['instance_number']}: {inst['instance_name']}")
```

### Delete an Instance

```python
manager.delete_instance(instance_number=1)
```

## Manual Instance Creation

If you prefer to create instances manually:

### 1. Copy the template

```bash
mkdir -p instances/instance-1
cp orchestrator/instance-template.yml instances/instance-1/docker-compose.yml
```

### 2. Replace variables

Edit `instances/instance-1/docker-compose.yml` and replace:
- `{INSTANCE_NUMBER}` → `1`
- `{INSTANCE_NAME}` → `main`
- `{VNC_PORT}` → `3000`
- `{RPYC_PORT}` → `8001`
- `{API_PORT}` → `8000`
- `{WEB_PORT}` → `80`
- `{MT5_LOGIN}` → Your MT5 login
- `{MT5_PASSWORD}` → Your MT5 password
- `{MT5_SERVER}` → Your MT5 server

### 3. Create frontend .env file

```bash
cat > instances/instance-1/frontend.env << EOF
VITE_INSTANCE_NUMBER=1
VITE_API_BASE_URL=/instance/1/api
VITE_SOCKET_URL=/instance/1
VITE_INSTANCE_NAME=main
EOF
```

### 4. Start the instance

```bash
cd instances/instance-1
docker-compose up -d
```

## Accessing Instances

Once the proxy and instances are running:

| Component | URL |
|-----------|-----|
| Orchestrator Dashboard | http://localhost/ |
| Orchestrator API | http://localhost/api/orchestrator |
| Instance 1 Frontend | http://localhost/instance/1 |
| Instance 1 API | http://localhost/instance/1/api |
| Instance 1 Socket.IO | http://localhost/instance/1/socket.io |
| Instance 2 Frontend | http://localhost/instance/2 |
| Instance 2 API | http://localhost/instance/2/api |

## Troubleshooting

### CORS Errors

**Problem:** Frontend shows CORS errors
**Solution:** Ensure nginx proxy is running and backend CORS_ORIGINS is set correctly

```bash
# Check proxy status
docker ps | grep nginx

# Check backend CORS config
grep CORS_ORIGINS backend/.env
```

### 502 Bad Gateway

**Problem:** Nginx returns 502 errors
**Solution:** Backend instance may not be running

```bash
# Check if backend is running
curl http://localhost:8000/health

# Check nginx logs
docker logs institutional_nginx_proxy
```

### WebSocket Connection Failed

**Problem:** Socket.IO connection fails
**Solution:** Verify Socket.IO path configuration

```javascript
// frontend/src/services/api.js
// Should have:
path: SOCKET_URL ? `${SOCKET_URL}/socket.io` : '/socket.io',
```

### Instance Not Accessible

**Problem:** Can't access /instance/N
**Solution:**
1. Verify instance is in nginx config
2. Check instance is running
3. Verify port allocation matches nginx upstream

```bash
# Check nginx config
cat nginx/nginx.conf | grep "instance_${N}"

# Check if ports are in use
netstat -an | grep "LISTEN" | grep "8000"
```

## Adding More Instances to Nginx

If you need to support more than 5 instances, edit `nginx/nginx.conf`:

```nginx
# Add upstream definitions
upstream instance_6_frontend {
    server host.docker.internal:85;
}
upstream instance_6_backend {
    server host.docker.internal:8010;
}

# Add location blocks
location /instance/6/api/ {
    proxy_pass http://instance_6_backend/api/;
    # ... (copy from existing instance)
}

location /instance/6/socket.io/ {
    proxy_pass http://instance_6_backend/socket.io/;
    # ... (copy from existing instance)
}

location /instance/6/ {
    proxy_pass http://instance_6_frontend/;
    # ... (copy from existing instance)
}
```

Then reload nginx:

```bash
docker-compose -f docker-compose.proxy.yml restart
```

## Production Deployment

For production, add SSL/TLS:

### 1. Generate SSL Certificate

```bash
# Using Let's Encrypt
certbot certonly --standalone -d yourdomain.com
```

### 2. Update nginx config

```nginx
server {
    listen 443 ssl http2;
    server_name yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    # ... rest of config
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name yourdomain.com;
    return 301 https://$server_name$request_uri;
}
```

### 3. Update CORS origins

```env
# backend/.env
CORS_ORIGINS=https://yourdomain.com
```

## Performance Tuning

For high-traffic deployments:

```nginx
# nginx.conf
events {
    worker_connections 4096;
}

http {
    # Enable caching
    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=my_cache:10m max_size=10g inactive=60m;

    # Increase buffer sizes
    proxy_buffer_size 128k;
    proxy_buffers 8 256k;
    proxy_busy_buffers_size 512k;
}
```

## Monitoring

### Nginx Access Logs

```bash
# View access logs
docker exec institutional_nginx_proxy tail -f /var/log/nginx/access.log

# View error logs
docker exec institutional_nginx_proxy tail -f /var/log/nginx/error.log
```

### Health Checks

```bash
# Proxy health
curl http://localhost/health

# Instance health
curl http://localhost/instance/1/api/health
```

## Summary

The reverse proxy architecture provides:

1. **Unified Access** - All services through one domain
2. **CORS Solution** - No cross-origin issues
3. **Scalability** - Easy to add new instances
4. **Production Ready** - SSL/TLS support
5. **Maintainable** - Clear routing structure

For questions or issues, refer to the troubleshooting section or check nginx logs.
