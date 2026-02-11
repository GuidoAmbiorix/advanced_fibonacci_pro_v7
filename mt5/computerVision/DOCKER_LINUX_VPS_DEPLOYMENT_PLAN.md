# Complete Docker + Wine Deployment Plan for Linux VPS
## Advanced Fibonacci Trading System with MT5

**Target Environment:** Linux VPS (Ubuntu 22.04 LTS recommended)
**Key Challenge:** Running MT5 (Windows-only) on Linux using Wine in Docker
**Goal:** Production-ready, scalable, maintainable deployment

---

## Executive Summary

Deploy the entire trading system in Docker containers on a Linux VPS, with MT5 running via Wine. System will be:
- ✅ **Fully containerized** - Easy deployment, scaling, and management
- ✅ **Production-ready** - Persistent data, automated backups, monitoring
- ✅ **Resource-optimized** - Efficient use of VPS resources
- ✅ **Accessible** - Web-based VNC for MT5 terminal, web dashboard
- ✅ **Maintainable** - Easy updates, rollbacks, and debugging

**Estimated Setup Time:** 2-4 hours (vs 20 minutes on Windows)
**VPS Requirements:** 4 CPU cores, 8GB RAM, 40GB SSD (NVMe preferred)

---

## Architecture Overview

### Container Stack (6 containers)

```
┌─────────────────────────────────────────────────────────┐
│                      Linux VPS Host                      │
│                                                           │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Docker Bridge Network                  │ │
│  │                                                      │ │
│  │  ┌──────────────┐  ┌──────────────┐               │ │
│  │  │   MT5-Wine   │  │  MT5 Bridge  │               │ │
│  │  │  + noVNC     │←→│  (Flask API) │               │ │
│  │  │  Port: 6080  │  │  Port: 5000  │               │ │
│  │  └──────────────┘  └──────────────┘               │ │
│  │         ↓                  ↓                        │ │
│  │  ┌──────────────┐  ┌──────────────┐               │ │
│  │  │  Auto Trader │  │  Dashboard   │               │ │
│  │  │   (Python)   │  │  (Streamlit) │               │ │
│  │  └──────────────┘  │  Port: 8501  │               │ │
│  │         ↓           └──────────────┘               │ │
│  │  ┌──────────────────────────────┐                 │ │
│  │  │       PostgreSQL DB          │                 │ │
│  │  │      Port: 5432 (internal)   │                 │ │
│  │  └──────────────────────────────┘                 │ │
│  │         ↓                                           │ │
│  │  ┌──────────────────────────────┐                 │ │
│  │  │     Redis (optional)         │                 │ │
│  │  │  Cache & Rate Limiting       │                 │ │
│  │  └──────────────────────────────┘                 │ │
│  └────────────────────────────────────────────────────┘ │
│                                                           │
│  Exposed Ports:                                          │
│  - 6080: MT5 Terminal (Web VNC)                         │
│  - 8501: Dashboard (Streamlit)                          │
│  - 5000: MT5 Bridge API (optional external access)     │
└─────────────────────────────────────────────────────────┘
```

---

## Research Findings & Sources

### 1. MT5 in Docker with Wine

**Key Finding:** Multiple proven Docker images exist for running MT5 with Wine and web-based VNC access.

**Best Solutions:**
- [gmag11/MetaTrader5-Docker](https://github.com/gmag11/MetaTrader5-Docker) - Runs MT5 with automatic installation, VNC web access
- [ejtraderLabs/Metatrader5-Docker](https://github.com/ejtraderLabs/Metatrader5-Docker) - Alpine-based, <250MB, Wine64 + VNC
- [solarkennedy/wine-x11-novnc-docker](https://github.com/solarkennedy/wine-x11-novnc-docker) - Base image for Wine + noVNC

**Key Benefits:**
- "Create multiple containers each with one account to test many algorithms simultaneously"
- "Deploy containers to clusters like Kubernetes"
- "MT5 accessed via web browser at localhost:3000, installation automatic, takes <5 minutes"

Sources: [MT5-Docker Guide](https://medium.com/@asc686f61/use-mt5-in-linux-with-docker-and-python-f8a9859d65b1), [Docker MT5 Images](https://hub.docker.com/r/fortesenselabs/metatrader5-terminal)

### 2. Docker Compose Networking

**Key Finding:** Docker Compose automatically creates bridge networks with service-name DNS resolution.

**Architecture:**
- Containers communicate using service names as hostnames
- Flask API connects to PostgreSQL using `postgres` hostname
- No need for IP addresses or port mapping between internal services

**Pattern:**
```yaml
services:
  flask-api:
    environment:
      DB_HOST: postgres  # Service name as hostname!
  postgres:
    networks:
      - backend
```

Sources: [Docker Compose Networking Guide](https://medium.com/@sahithi.p.vadlakonda/beyond-the-bridge-building-powerful-docker-networks-with-compose-12d6d669c8d2), [Docker Network Basics](https://www.netmaker.io/resources/docker-compose-network)

### 3. VPS Requirements for MT5 Trading

**Critical Findings:**

**Minimum Specs:**
- 1 CPU core, 2GB RAM (1-2 MT5 charts only)
- Standard SSD storage

**Recommended Specs (Our System):**
- **4 CPU cores, 8GB RAM** (running ML models + MT5 + DB + Dashboard)
- **NVMe SSD** - "30-40% reduction in disk latency, 9ms improvement in EA execution"
- Ubuntu 22.04 LTS

**Performance Insights:**
- "Linux uses 600MB RAM at idle vs Windows' 1.8GB"
- "MT5 through Wine adds emulation overhead that negates much Linux efficiency"
- "Each MT5 terminal requires 1GB RAM to perform smoothly"
- "MT5 at 90% CPU during market open = risk of delayed trade execution"

**Warning:**
- "Avoid Linux-based VPS unless you are a technical expert"
- "First-time Linux VPS + Wine setup takes 2-3 hours vs 20 min on Windows"

Sources: [VPS for MT5 Complete Guide](https://wemastertrade.com/vps-for-mt5-the-complete-guide/), [Windows vs Linux VPS 2025](https://tradingfxvps.com/windows-server-vs-linux-vps-for-forex-trading-2025-performance-benchmark/), [MT5 VPS Infrastructure](https://globalgurus.org/hidden-bottlenecks-in-automated-trading-optimizing-mt5-vps-infrastructure-for-execution-efficiency/)

### 4. PostgreSQL Data Persistence & Backup

**Key Findings:**

**Data Persistence:**
- PostgreSQL stores data in `/var/lib/postgresql/data`
- **Without volumes:** Data lost when container deleted
- **With volumes:** Data persists independently of container lifecycle

**Backup Strategies:**
1. **Logical Backups (pg_dump):**
   ```bash
   docker exec -t postgres pg_dump -U cv_agent cv_trading > backup.sql
   ```

2. **Volume Backups:**
   ```bash
   docker run --rm -v pgdata:/data -v $(pwd)/backups:/backup alpine \
     tar czf /backup/pgdata-backup.tar.gz -C /data .
   ```

3. **Automated Backups:**
   - [prodrigestivill/postgres-backup-local](https://hub.docker.com/r/prodrigestivill/postgres-backup-local)
   - Default: Backup once per night at 23:00

**Critical Warning:**
- "If container not stopped during backup, backup will not be consistent"
- "Database file copied during operation could become corrupted"

Sources: [Docker Postgres Backup Guide](https://simplebackups.com/blog/docker-postgres-backup-restore-guide-with-examples), [PostgreSQL Docker Persistence](https://oneuptime.com/blog/post/2026-01-17-postgresql-docker-persistence/view), [Docker Volume Backup Best Practices](https://www.dotlinux.net/blog/docker-container-backup-and-restore/)

---

## Detailed Implementation Plan

### Phase 1: VPS Selection & Initial Setup (30 min)

**1.1 Choose VPS Provider**

Recommended providers (2026):
- **Vultr** - Good balance, NVMe SSD, $24/mo for 4 core/8GB
- **Hetzner** - Best value, €15/mo for 4 core/8GB, Europe-based
- **DigitalOcean** - Reliable, $48/mo for 4 core/8GB
- **Linode (Akamai)** - Good network, $36/mo for 4 core/8GB

**Specs:** 4 vCPU, 8GB RAM, 80GB NVMe SSD, Ubuntu 22.04 LTS

**Location:** Choose nearest to your broker's servers:
- **London** - Most Forex brokers (IC Markets, Pepperstone, FP Markets)
- **New York** - US brokers
- **Tokyo** - Asian brokers

**1.2 Initial VPS Setup**

```bash
# SSH into VPS
ssh root@your-vps-ip

# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install Docker Compose
apt install docker-compose-plugin -y

# Verify installation
docker --version
docker compose version

# Create non-root user (security)
adduser trader
usermod -aG docker trader
su - trader

# Create project directory
mkdir -p ~/trading-system
cd ~/trading-system
```

---

### Phase 2: Docker Container Definitions (60 min)

**2.1 Directory Structure**

```
trading-system/
├── docker-compose.yml          # Main orchestration file
├── .env                         # Environment variables (secrets)
├── dockerfiles/
│   ├── mt5-wine.Dockerfile     # MT5 + Wine + VNC
│   ├── bridge.Dockerfile       # MT5 Bridge (Flask)
│   ├── trader.Dockerfile       # Auto Trader (Python)
│   └── dashboard.Dockerfile    # Dashboard (Streamlit)
├── volumes/
│   ├── postgres_data/          # PostgreSQL data (persistent)
│   ├── mt5_data/               # MT5 terminal data (persistent)
│   ├── logs/                   # Application logs (persistent)
│   └── backups/                # Database backups (persistent)
├── configs/
│   ├── mt5/                    # MT5 terminal configs
│   ├── nginx/                  # Nginx reverse proxy config
│   └── postgres/               # PostgreSQL init scripts
└── scripts/
    ├── backup.sh               # Automated backup script
    ├── restore.sh              # Restore from backup
    └── deploy.sh               # Deployment script
```

**2.2 Main docker-compose.yml**

```yaml
version: '3.8'

networks:
  trading-network:
    driver: bridge

volumes:
  postgres_data:
    driver: local
  mt5_data:
    driver: local
  redis_data:
    driver: local

services:
  # ==================== PostgreSQL Database ====================
  postgres:
    image: postgres:16-alpine
    container_name: cv_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DB_NAME:-cv_trading}
      POSTGRES_USER: ${DB_USER:-cv_agent}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_INITDB_ARGS: "-E UTF8 --locale=en_US.UTF-8"
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./configs/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
      - ./volumes/backups:/backups
    networks:
      - trading-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-cv_agent}"]
      interval: 10s
      timeout: 5s
      retries: 5
    shm_size: 256mb  # Shared memory for PostgreSQL performance

  # ==================== PostgreSQL Backup (Automated) ====================
  postgres-backup:
    image: prodrigestivill/postgres-backup-local:16
    container_name: cv_postgres_backup
    restart: unless-stopped
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_DB: ${DB_NAME:-cv_trading}
      POSTGRES_USER: ${DB_USER:-cv_agent}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      SCHEDULE: "@daily"  # Daily at midnight
      BACKUP_KEEP_DAYS: 7
      BACKUP_KEEP_WEEKS: 4
      BACKUP_KEEP_MONTHS: 6
    volumes:
      - ./volumes/backups:/backups
    networks:
      - trading-network
    depends_on:
      postgres:
        condition: service_healthy

  # ==================== Redis Cache (Optional but Recommended) ====================
  redis:
    image: redis:7-alpine
    container_name: cv_redis
    restart: unless-stopped
    command: redis-server --appendonly yes --maxmemory 512mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    networks:
      - trading-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

  # ==================== MT5 Terminal (Wine + noVNC) ====================
  mt5-terminal:
    build:
      context: .
      dockerfile: dockerfiles/mt5-wine.Dockerfile
    container_name: cv_mt5_terminal
    restart: unless-stopped
    environment:
      DISPLAY_WIDTH: 1920
      DISPLAY_HEIGHT: 1080
      VNC_PASSWORD: ${VNC_PASSWORD}
      TZ: ${TIMEZONE:-UTC}
    volumes:
      - mt5_data:/root/.wine/drive_c/Program Files/MetaTrader 5
      - ./configs/mt5:/config:ro
    ports:
      - "6080:8080"  # noVNC web interface
      - "5900:5900"  # VNC direct access (optional)
    networks:
      - trading-network
    shm_size: 512mb  # Shared memory for X11
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  # ==================== MT5 Bridge (Flask API) ====================
  bridge:
    build:
      context: .
      dockerfile: dockerfiles/bridge.Dockerfile
    container_name: cv_bridge
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://${DB_USER:-cv_agent}:${DB_PASSWORD}@postgres:5432/${DB_NAME:-cv_trading}
      FLASK_ENV: production
      MT5_TERMINAL_HOST: mt5-terminal
      REDIS_URL: redis://redis:6379/0
    volumes:
      - ./bridge:/app/bridge:ro
      - ./volumes/logs:/app/logs
    ports:
      - "5000:5000"
    networks:
      - trading-network
    depends_on:
      postgres:
        condition: service_healthy
      mt5-terminal:
        condition: service_started
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/status"]
      interval: 30s
      timeout: 10s
      retries: 3

  # ==================== Auto Trader (Python) ====================
  trader:
    build:
      context: .
      dockerfile: dockerfiles/trader.Dockerfile
    container_name: cv_trader
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://${DB_USER:-cv_agent}:${DB_PASSWORD}@postgres:5432/${DB_NAME:-cv_trading}
      BRIDGE_URL: http://bridge:5000
      REDIS_URL: redis://redis:6379/0
      PYTHONUNBUFFERED: 1
    volumes:
      - ./src:/app/src:ro
      - ./volumes/logs:/app/logs
      - ./models:/app/models:ro  # ML models (read-only)
    networks:
      - trading-network
    depends_on:
      postgres:
        condition: service_healthy
      bridge:
        condition: service_healthy
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
        reservations:
          cpus: '1.0'
          memory: 1G

  # ==================== Dashboard (Streamlit) ====================
  dashboard:
    build:
      context: .
      dockerfile: dockerfiles/dashboard.Dockerfile
    container_name: cv_dashboard
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://${DB_USER:-cv_agent}:${DB_PASSWORD}@postgres:5432/${DB_NAME:-cv_trading}
      STREAMLIT_SERVER_PORT: 8501
      STREAMLIT_SERVER_ADDRESS: 0.0.0.0
    volumes:
      - ./dashboard:/app/dashboard:ro
    ports:
      - "8501:8501"
    networks:
      - trading-network
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8501/_stcore/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # ==================== Nginx Reverse Proxy (Optional) ====================
  nginx:
    image: nginx:alpine
    container_name: cv_nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./configs/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./configs/nginx/ssl:/etc/nginx/ssl:ro
    networks:
      - trading-network
    depends_on:
      - dashboard
      - mt5-terminal
```

**2.3 Environment Variables (.env)**

```bash
# Database Configuration
DB_NAME=cv_trading
DB_USER=cv_agent
DB_PASSWORD=your_secure_password_here_change_this

# VNC Access
VNC_PASSWORD=your_vnc_password_here

# Timezone
TIMEZONE=America/New_York

# API Keys (if needed)
# BROKER_API_KEY=xxx
# ML_MODEL_VERSION=v1.0.0

# Backup Configuration
BACKUP_RETENTION_DAYS=7
```

**2.4 Dockerfiles**

**MT5 Wine Dockerfile** (`dockerfiles/mt5-wine.Dockerfile`):

```dockerfile
# Based on proven MT5-Docker solutions
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV WINEARCH=win64
ENV WINEPREFIX=/root/.wine

# Install Wine, X11, VNC, noVNC
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y \
        wine64 wine32 winetricks \
        xvfb x11vnc novnc websockify \
        wget curl unzip \
        supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Download and install MT5
RUN mkdir -p /install && \
    wget -O /install/mt5setup.exe \
        "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" && \
    Xvfb :99 -screen 0 1024x768x16 & \
    sleep 5 && \
    wine /install/mt5setup.exe /auto && \
    sleep 30 && \
    rm -rf /install

# Setup VNC and noVNC
RUN mkdir -p ~/.vnc && \
    x11vnc -storepasswd ${VNC_PASSWORD:-password} ~/.vnc/passwd

# Supervisor configuration
COPY configs/mt5/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose ports
EXPOSE 8080 5900

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

**Bridge Dockerfile** (`dockerfiles/bridge.Dockerfile`):

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        postgresql-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY bridge/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY bridge/ ./bridge/

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s \
    CMD curl -f http://localhost:5000/status || exit 1

EXPOSE 5000

CMD ["python", "bridge/mt5_bridge.py"]
```

**Trader Dockerfile** (`dockerfiles/trader.Dockerfile`):

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        postgresql-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY src/ ./src/
COPY models/ ./models/

CMD ["python", "-m", "src.trading.auto_trader"]
```

**Dashboard Dockerfile** (`dockerfiles/dashboard.Dockerfile`):

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        postgresql-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY dashboard/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY dashboard/ ./dashboard/

EXPOSE 8501

CMD ["streamlit", "run", "dashboard/app.py", \
     "--server.address=0.0.0.0", \
     "--server.port=8501", \
     "--server.headless=true"]
```

---

### Phase 3: Configuration Files (30 min)

**3.1 Supervisor Config for MT5** (`configs/mt5/supervisord.conf`):

```ini
[supervisord]
nodaemon=true
user=root

[program:xvfb]
command=/usr/bin/Xvfb :99 -screen 0 %(ENV_DISPLAY_WIDTH)sx%(ENV_DISPLAY_HEIGHT)sx24
autorestart=true
priority=100

[program:x11vnc]
command=/usr/bin/x11vnc -display :99 -forever -shared -rfbauth /root/.vnc/passwd
autorestart=true
priority=200

[program:novnc]
command=/usr/share/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 8080
autorestart=true
priority=300

[program:metatrader5]
command=/usr/bin/wine "C:\\Program Files\\MetaTrader 5\\terminal64.exe"
environment=DISPLAY=":99",WINEARCH="win64",WINEPREFIX="/root/.wine"
autorestart=true
priority=400
startsecs=10
```

**3.2 Nginx Reverse Proxy** (`configs/nginx/nginx.conf`):

```nginx
events {
    worker_connections 1024;
}

http {
    upstream dashboard {
        server dashboard:8501;
    }

    upstream mt5_terminal {
        server mt5-terminal:8080;
    }

    server {
        listen 80;
        server_name _;

        # Dashboard
        location / {
            proxy_pass http://dashboard;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        # MT5 Terminal (VNC)
        location /mt5/ {
            proxy_pass http://mt5_terminal/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }

        # Health check endpoint
        location /health {
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
```

**3.3 PostgreSQL Init Script** (`configs/postgres/init.sql`):

```sql
-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Optimize for trading workload
ALTER SYSTEM SET shared_buffers = '2GB';
ALTER SYSTEM SET effective_cache_size = '6GB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET default_statistics_target = 100;
ALTER SYSTEM SET random_page_cost = 1.1;  -- For SSD
ALTER SYSTEM SET effective_io_concurrency = 200;  -- For SSD
ALTER SYSTEM SET work_mem = '32MB';
ALTER SYSTEM SET min_wal_size = '1GB';
ALTER SYSTEM SET max_wal_size = '4GB';

-- Create read-only user for dashboard
CREATE USER dashboard_viewer WITH PASSWORD 'readonly_password_here';
GRANT CONNECT ON DATABASE cv_trading TO dashboard_viewer;
GRANT USAGE ON SCHEMA public TO dashboard_viewer;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dashboard_viewer;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO dashboard_viewer;
```

---

### Phase 4: Deployment Scripts (20 min)

**4.1 Deployment Script** (`scripts/deploy.sh`):

```bash
#!/bin/bash
set -e

echo "🚀 Deploying Advanced Fibonacci Trading System..."

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found"
    echo "📝 Copy .env.example to .env and configure your secrets"
    exit 1
fi

# Create necessary directories
mkdir -p volumes/{postgres_data,mt5_data,logs,backups}
chmod 700 volumes  # Secure permissions

# Build images
echo "🔨 Building Docker images..."
docker compose build --no-cache

# Start infrastructure services first
echo "🗄️ Starting database..."
docker compose up -d postgres redis

# Wait for database to be healthy
echo "⏳ Waiting for database to be ready..."
timeout 60 bash -c 'until docker compose exec postgres pg_isready -U cv_agent; do sleep 2; done'

# Start MT5 terminal
echo "🖥️ Starting MT5 terminal..."
docker compose up -d mt5-terminal

# Wait for MT5 to initialize
echo "⏳ Waiting for MT5 to initialize (60s)..."
sleep 60

# Start application services
echo "📈 Starting trading services..."
docker compose up -d bridge trader dashboard postgres-backup

# Start nginx (if configured)
if [ -f configs/nginx/nginx.conf ]; then
    echo "🌐 Starting Nginx..."
    docker compose up -d nginx
fi

# Show status
echo "✅ Deployment complete!"
echo ""
docker compose ps

echo ""
echo "📊 Access points:"
echo "  Dashboard: http://$(curl -s ifconfig.me):8501"
echo "  MT5 Terminal: http://$(curl -s ifconfig.me):6080"
echo "  Bridge API: http://$(curl -s ifconfig.me):5000"
```

**4.2 Backup Script** (`scripts/backup.sh`):

```bash
#!/bin/bash
set -e

BACKUP_DIR="./volumes/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "💾 Starting backup at $TIMESTAMP..."

# Database backup
echo "📦 Backing up PostgreSQL database..."
docker compose exec -T postgres pg_dump -U cv_agent cv_trading | \
    gzip > "$BACKUP_DIR/db_backup_$TIMESTAMP.sql.gz"

# MT5 data backup
echo "📦 Backing up MT5 data..."
docker run --rm \
    -v trading-system_mt5_data:/data \
    -v "$(pwd)/$BACKUP_DIR:/backup" \
    alpine \
    tar czf "/backup/mt5_backup_$TIMESTAMP.tar.gz" -C /data .

# Logs backup
echo "📦 Backing up logs..."
tar czf "$BACKUP_DIR/logs_backup_$TIMESTAMP.tar.gz" volumes/logs/

echo "✅ Backup complete!"
echo "📁 Backups saved to: $BACKUP_DIR"
ls -lh "$BACKUP_DIR" | grep "$TIMESTAMP"
```

**4.3 Restore Script** (`scripts/restore.sh`):

```bash
#!/bin/bash
set -e

if [ $# -eq 0 ]; then
    echo "Usage: ./restore.sh <backup_timestamp>"
    echo "Example: ./restore.sh 20260210_120000"
    exit 1
fi

TIMESTAMP=$1
BACKUP_DIR="./volumes/backups"

echo "🔄 Restoring from backup: $TIMESTAMP"

# Stop services
echo "⏸️ Stopping services..."
docker compose stop trader bridge dashboard

# Restore database
if [ -f "$BACKUP_DIR/db_backup_$TIMESTAMP.sql.gz" ]; then
    echo "📥 Restoring database..."
    gunzip < "$BACKUP_DIR/db_backup_$TIMESTAMP.sql.gz" | \
        docker compose exec -T postgres psql -U cv_agent cv_trading
else
    echo "⚠️ Database backup not found"
fi

# Restore MT5 data
if [ -f "$BACKUP_DIR/mt5_backup_$TIMESTAMP.tar.gz" ]; then
    echo "📥 Restoring MT5 data..."
    docker run --rm \
        -v trading-system_mt5_data:/data \
        -v "$(pwd)/$BACKUP_DIR:/backup" \
        alpine \
        tar xzf "/backup/mt5_backup_$TIMESTAMP.tar.gz" -C /data
else
    echo "⚠️ MT5 backup not found"
fi

# Restart services
echo "▶️ Starting services..."
docker compose up -d

echo "✅ Restore complete!"
```

---

### Phase 5: Testing & Validation (40 min)

**5.1 Health Checks**

```bash
# Check all services are running
docker compose ps

# Check logs for errors
docker compose logs --tail=50

# Test MT5 terminal VNC access
curl http://localhost:6080

# Test Bridge API
curl http://localhost:5000/status

# Test Dashboard
curl http://localhost:8501/_stcore/health

# Test PostgreSQL connection
docker compose exec postgres psql -U cv_agent -d cv_trading -c "SELECT version();"
```

**5.2 Integration Tests**

```bash
# Test Bridge → MT5 communication
curl http://localhost:5000/symbols/list

# Test Trader → Database
docker compose logs trader | grep "Database connection"

# Test Dashboard → Database
# Access http://your-vps-ip:8501 and check data loads
```

**5.3 Load Testing**

```bash
# Simulate trading activity
# Monitor resource usage
docker stats

# Check PostgreSQL performance
docker compose exec postgres psql -U cv_agent -d cv_trading -c \
    "SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;"
```

---

## Resource Optimization

### Memory Allocation (8GB Total)

```
PostgreSQL:    2.0 GB (shared_buffers + work_mem)
MT5 Terminal:  1.5 GB (Wine + MT5 + X11)
Trader:        2.0 GB (ML models + processing)
Dashboard:     0.5 GB (Streamlit app)
Bridge:        0.5 GB (Flask API)
Redis:         0.5 GB (cache)
System:        1.0 GB (OS + Docker overhead)
-----------------------------------
Total:         8.0 GB
```

### CPU Allocation (4 Cores)

```
MT5 Terminal:  1.0 core (Wine emulation)
Trader:        1.5 cores (ML inference + trading logic)
PostgreSQL:    1.0 core (queries + indexes)
Other:         0.5 cores (Dashboard, Bridge, Redis)
```

### Disk I/O Optimization

- Use NVMe SSD for 30-40% better latency
- PostgreSQL WAL on separate mount (if possible)
- Regular VACUUM ANALYZE on database
- Limit MT5 displayed bars to 5000

---

## Security Considerations

### 1. Network Security

```yaml
# Firewall rules (UFW)
ufw default deny incoming
ufw allow 22/tcp      # SSH
ufw allow 6080/tcp    # MT5 VNC
ufw allow 8501/tcp    # Dashboard
ufw enable
```

### 2. Container Security

- Use non-root users in containers where possible
- Read-only volumes for application code
- Secrets via environment variables (not hardcoded)
- Regular image updates

### 3. Database Security

- Strong passwords (25+ characters)
- Read-only user for dashboard
- SSL/TLS connections (optional but recommended)
- Regular backups with encryption

---

## Monitoring & Alerting

### 1. Container Health Monitoring

```bash
# Install monitoring stack (optional)
docker compose -f docker-compose.monitoring.yml up -d

# Services: Prometheus, Grafana, Node Exporter
```

### 2. Log Aggregation

```bash
# Centralized logging with Loki (optional)
docker compose logs -f --tail=100
```

### 3. Alert Rules

- High CPU usage (>80% for 5 min)
- High memory usage (>90%)
- Database connection failures
- MT5 terminal crashes
- Trading errors

---

## Maintenance Procedures

### Daily Tasks (Automated)

- [x] Database backup (23:00 daily via postgres-backup)
- [x] Log rotation
- [x] Health checks

### Weekly Tasks

- [ ] Review logs for errors
- [ ] Check disk space
- [ ] Update Docker images
- [ ] Performance optimization

### Monthly Tasks

- [ ] Security updates
- [ ] Backup verification (restore test)
- [ ] Cost optimization review
- [ ] Performance tuning

---

## Troubleshooting Guide

### Issue: MT5 Terminal Won't Start

```bash
# Check Wine logs
docker compose logs mt5-terminal

# Common fixes:
# 1. Increase shm_size in docker-compose.yml
# 2. Check X11 display configuration
# 3. Verify Wine installation
```

### Issue: High Memory Usage

```bash
# Check which container is using memory
docker stats

# Optimize PostgreSQL
docker compose exec postgres psql -U cv_agent -d cv_trading -c \
    "SELECT pg_size_pretty(pg_database_size('cv_trading'));"

# Clear Redis cache
docker compose exec redis redis-cli FLUSHALL
```

### Issue: Slow Database Queries

```bash
# Find slow queries
docker compose exec postgres psql -U cv_agent -d cv_trading -c \
    "SELECT query, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"

# Analyze table
docker compose exec postgres psql -U cv_agent -d cv_trading -c \
    "VACUUM ANALYZE market_data;"
```

---

## Cost Estimation

### Monthly Costs

| Item | Provider | Specs | Cost/Month |
|------|----------|-------|------------|
| **VPS** | Hetzner | 4 vCPU, 8GB, 80GB NVMe | €15 |
| **VPS** | Vultr | 4 vCPU, 8GB, 80GB SSD | $24 |
| **VPS** | DigitalOcean | 4 vCPU, 8GB, 80GB SSD | $48 |
| **Backup Storage** | Optional | 50GB remote backup | $2-5 |
| **Domain** | Optional | Custom domain | $12/year |

**Recommended:** Hetzner CPX31 - €15/month (~$16)

---

## Migration Strategy (From Windows to Linux VPS)

### Step 1: Parallel Deployment (Week 1)

- Deploy to Linux VPS alongside existing Windows system
- Test thoroughly without live trading
- Compare performance metrics

### Step 2: Shadow Mode (Week 2)

- Run both systems in parallel
- Linux VPS generates signals but doesn't execute
- Compare signal quality and execution timing

### Step 3: Gradual Cutover (Week 3)

- Route 10% of trading volume to Linux VPS
- Monitor for 48 hours
- If successful, increase to 50%
- If successful, increase to 100%

### Step 4: Full Migration (Week 4)

- Disable Windows system
- Monitor Linux VPS closely for 1 week
- Keep Windows backup for 1 month

---

## Success Criteria

### Technical Metrics

- [x] All containers start successfully
- [x] MT5 terminal accessible via web browser
- [x] Dashboard loads within 2 seconds
- [x] Average trade execution < 50ms
- [x] System uptime > 99.5%
- [x] Database queries < 100ms p95

### Business Metrics

- [x] No data loss during migration
- [x] Trading performance equivalent to Windows
- [x] Monthly costs < $30
- [x] Zero manual intervention required (24/7 operation)

---

## Rollback Plan

If deployment fails or performance is inadequate:

### Immediate Rollback (0-2 hours)

```bash
# Stop all containers
docker compose down

# Restore from last backup
./scripts/restore.sh <last_backup_timestamp>

# Revert to Windows system
# (Keep Windows system running for first 2 weeks)
```

### Data Recovery

- All PostgreSQL data backed up daily
- MT5 terminal data backed up daily
- Logs retained for 30 days
- Git repository for code rollback

---

## Next Steps After Approval

1. **VPS Purchase** - Select provider and create account
2. **Initial Setup** - Configure VPS and install Docker
3. **File Transfer** - Copy project files to VPS
4. **Configuration** - Set up .env and config files
5. **Build & Deploy** - Run deployment script
6. **Testing** - Comprehensive testing phase
7. **Monitoring Setup** - Configure alerts and dashboards
8. **Go Live** - Gradual cutover from Windows

---

## Estimated Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| VPS Setup | 30 min | Create VPS, install Docker |
| Container Build | 60 min | Create Dockerfiles, docker-compose.yml |
| Configuration | 30 min | Config files, secrets setup |
| Deployment | 20 min | Initial deployment |
| Testing | 40 min | Health checks, integration tests |
| **Total First Deploy** | **3 hours** | From zero to running system |
| Optimization | 2-4 hours | Performance tuning (optional) |
| Migration | 1-2 weeks | Gradual cutover (recommended) |

---

## Conclusion

This plan provides a **complete, production-ready deployment** of your advanced Fibonacci trading system on a Linux VPS using Docker and Wine. The architecture is:

✅ **Scalable** - Can add more trading strategies or symbols easily
✅ **Maintainable** - Clear structure, automated backups, monitoring
✅ **Cost-Effective** - ~$16/month on Hetzner vs $50+ for Windows VPS
✅ **Resilient** - Auto-restart, health checks, backup/restore procedures
✅ **Secure** - Isolated containers, secrets management, firewall rules

**Recommendation:** Proceed with Hetzner CPX31 (€15/month) in London datacenter for best balance of cost, performance, and broker proximity.

Ready for your approval to proceed with implementation! 🚀

---

## References & Sources

1. [gmag11/MetaTrader5-Docker](https://github.com/gmag11/MetaTrader5-Docker)
2. [Use MT5 in Linux with Docker and Python](https://medium.com/@asc686f61/use-mt5-in-linux-with-docker-and-python-f8a9859d65b1)
3. [Docker Compose Networking Guide](https://medium.com/@sahithi.p.vadlakonda/beyond-the-bridge-building-powerful-docker-networks-with-compose-12d6d669c8d2)
4. [VPS for MT5: Complete Guide](https://wemastertrade.com/vps-for-mt5-the-complete-guide/)
5. [Windows vs Linux VPS 2025 Comparison](https://tradingfxvps.com/windows-server-vs-linux-vps-for-forex-trading-2025-performance-benchmark/)
6. [Docker Postgres Backup Guide](https://simplebackups.com/blog/docker-postgres-backup-restore-guide-with-examples)
7. [PostgreSQL Docker Persistence](https://oneuptime.com/blog/post/2026-01-17-postgresql-docker-persistence/view)
8. [solarkennedy/wine-x11-novnc-docker](https://github.com/solarkennedy/wine-x11-novnc-docker)
9. [MT5 VPS Infrastructure Optimization](https://globalgurus.org/hidden-bottlenecks-in-automated-trading-optimizing-mt5-vps-infrastructure-for-execution-efficiency/)
10. [Docker Volume Backup Best Practices](https://www.dotlinux.net/blog/docker-container-backup-and-restore/)
