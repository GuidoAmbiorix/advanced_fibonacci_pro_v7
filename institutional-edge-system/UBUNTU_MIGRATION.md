# Ubuntu Migration Guide

## Quick Start - 5 Steps to Ubuntu

### 1. Install Ubuntu Requirements
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
sudo apt install docker.io docker-compose git dos2unix curl -y

# Add user to docker group (no need for sudo)
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Transfer Project Files
```bash
# Option A: Clone from Git
git clone <your-repo> institutional-edge-system
cd institutional-edge-system

# Option B: Copy from Windows
# Use SCP, shared folders, or USB
```

### 3. Fix Scripts for Linux
```bash
# Fix line endings (Windows uses CRLF, Linux uses LF)
dos2unix start_all.sh start-proxy.sh

# Make scripts executable
chmod +x start_all.sh start-proxy.sh
```

### 4. Update Environment
```bash
# Edit .env file
nano .env

# Comment out Windows-specific path:
# MT5_PATH=C:\Program Files\...  (not needed in Docker)
```

### 5. Start System
```bash
# That's it!
./start_all.sh
```

## Verification

Check everything is running:
```bash
# View containers
docker ps

# Access URLs
curl http://localhost/health
curl http://localhost:9000

# View logs
docker logs institutional_nginx_proxy
docker logs institutional_rabbitmq
```

## Access Points

- **Fleet Commander**: http://localhost:9000/
- **RabbitMQ Management**: http://localhost:15672 (guest/guest)
- **Instance 1**: http://localhost:81/ (VNC: 3001)
- **Instance 2**: http://localhost:82/ (VNC: 3002)

## Common Issues

### "Permission denied" on scripts
```bash
chmod +x *.sh
```

### "bad interpreter" error
```bash
dos2unix start_all.sh
```

### "Cannot connect to Docker"
```bash
sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker
```

### "Network not found"
```bash
# Networks are created automatically by start_all.sh
# Or create manually:
docker network create bot-net
docker network create trading_network
```

## Stop Everything
```bash
docker-compose -f docker-compose.admin.yml down
docker-compose -f docker-compose.proxy.yml down
docker-compose -f docker-compose.shared.yml down
```

## Reset Database
```bash
docker-compose down -v
./start_all.sh
```

## What Works Exactly The Same

✓ All Docker Compose files
✓ All Python code
✓ All Vue.js code
✓ Port mappings
✓ Environment variables
✓ MT5 containers

## What Changed

- `.bat` → `.sh` scripts
- Windows paths → Linux paths (in .env)
- CRLF → LF line endings
- Script permissions (chmod +x)

That's it! Everything else works identically.
